"""Secure boot and interrupt-service behavior for the RCIF firmware model."""

import hashlib
import hmac
import struct
from dataclasses import dataclass

from .device import RcifDevice
from .protocol import Counter, DeviceStatus


MANIFEST_MAGIC = 0x52434657


@dataclass(frozen=True)
class FirmwareImage:
    payload: bytes
    security_version: int
    digest: bytes
    signature: bytes

    @classmethod
    def sign(cls, payload: bytes, security_version: int, root_key: bytes) -> "FirmwareImage":
        digest = hashlib.sha256(payload).digest()
        signed = struct.pack("<III", MANIFEST_MAGIC, len(payload), security_version) + digest
        signature = hmac.new(root_key, signed, hashlib.sha256).digest()
        return cls(payload, security_version, digest, signature)


class FirmwareController:
    """Firmware policy model. Root-key operations represent immutable ROM."""

    def __init__(self, device: RcifDevice, root_key: bytes, queue_entries: int = 16):
        if len(root_key) < 16:
            raise ValueError("simulation root key must contain at least 128 bits")
        self.device = device
        self._root_key = bytes(root_key)
        self.queue_entries = queue_entries
        self._next_physical_page = 0x1000

    def boot(self, image: FirmwareImage, lock_debug: bool = True) -> bool:
        self.device._increment(Counter.BOOT_ATTEMPTS)
        if not self._rom_verify(image):
            self.device._increment(Counter.BOOT_FAILURES)
            self.device.boot_failed = True
            self.device.secure_verified = False
            self.device.status = DeviceStatus.FATAL
            self.device.enabled = False
            return False
        try:
            self.device.initialize_queues(self.queue_entries)
        except ValueError:
            self.device._increment(Counter.BOOT_FAILURES)
            self.device.boot_failed = True
            self.device.status = DeviceStatus.FATAL
            return False
        self.device.secure_verified = True
        self.device.boot_failed = False
        self.device.firmware_version = image.security_version
        self.device.otp_minimum_version = max(
            self.device.otp_minimum_version, image.security_version
        )
        self.device.status = DeviceStatus.FIRMWARE_READY
        if lock_debug:
            self.device.debug_locked = True
        self.device.enable()
        return True

    def service_faults(self, budget: int = 16) -> int:
        if self.device.fault_ring is None:
            return 0
        recovered = 0
        for _ in range(budget):
            fault = self.device.fault_ring.pop()
            if fault is None:
                break
            if not fault.replayable or fault.retry_count >= 3:
                continue
            if fault.address not in self.device.kv_pages:
                self.device.kv_pages[fault.address] = self._next_physical_page
                self._next_physical_page += 1
            if self.device.replay(fault.request_id):
                self.device._increment(Counter.KV_RECOVERED)
                recovered += 1
        return recovered

    def _rom_verify(self, image: FirmwareImage) -> bool:
        if image.security_version < self.device.otp_minimum_version:
            return False
        digest = hashlib.sha256(image.payload).digest()
        if not hmac.compare_digest(digest, image.digest):
            return False
        signed = struct.pack(
            "<III", MANIFEST_MAGIC, len(image.payload), image.security_version
        ) + digest
        expected = hmac.new(self._root_key, signed, hashlib.sha256).digest()
        return hmac.compare_digest(expected, image.signature)

