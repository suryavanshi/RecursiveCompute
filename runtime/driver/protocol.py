"""Frozen Phase 8 queue and graph protocol types."""

from dataclasses import dataclass
from enum import IntEnum
from typing import Tuple


class DeviceStatus(IntEnum):
    BOOT_ROM = 1
    FIRMWARE_READY = 2
    RUNNING = 3
    FATAL = 0x80000000


class Status(IntEnum):
    OK = 0
    UNSUPPORTED = 1
    BAD_FLAGS = 2
    KV_MISS = 4
    GRAPH_INVALID = 13
    GRAPH_DEADLOCK = 14
    QUEUE_FULL = 16
    SECURITY = 17


class CommandOpcode(IntEnum):
    SUBMIT_GRAPH = 1
    KV_TRANSLATE = 2


class GraphOpcode(IntEnum):
    NOP = 0
    DMA = 1
    ATTENTION = 2
    TENSOR = 3
    COMPLETE = 15


class Counter(IntEnum):
    ACCEPTED = 0
    COMPLETED = 1
    ERRORS = 2
    FAULT_OVERFLOWS = 3
    KV_FAULTS = 4
    KV_RECOVERED = 5
    BOOT_ATTEMPTS = 6
    BOOT_FAILURES = 7
    GRAPH_NODES = 8
    QUEUE_ERRORS = 9


@dataclass(frozen=True)
class GraphNode:
    opcode: int
    node_id: int
    dependencies: int = 0
    operand0: int = 0
    operand1: int = 0
    flags: int = 0

    def encode(self) -> bytes:
        value = self._value()
        return value.to_bytes(16, "little")

    @classmethod
    def decode(cls, data: bytes) -> "GraphNode":
        if len(data) != 16:
            raise ValueError("a graph node is exactly 16 bytes")
        value = int.from_bytes(data, "little")
        if value >> 116:
            raise ValueError("reserved graph-node bits are nonzero")
        return cls(
            opcode=value & 0xF,
            flags=(value >> 4) & 0xF,
            node_id=(value >> 8) & 0xF,
            dependencies=(value >> 12) & 0xFF,
            operand0=(value >> 20) & ((1 << 64) - 1),
            operand1=(value >> 84) & ((1 << 32) - 1),
        )

    def _value(self) -> int:
        fields = (
            ("opcode", self.opcode, 4),
            ("flags", self.flags, 4),
            ("node_id", self.node_id, 4),
            ("dependencies", self.dependencies, 8),
            ("operand0", self.operand0, 64),
            ("operand1", self.operand1, 32),
        )
        for name, value, width in fields:
            if value < 0 or value >= (1 << width):
                raise ValueError("{} does not fit {} bits".format(name, width))
        return (
            self.opcode
            | (self.flags << 4)
            | (self.node_id << 8)
            | (self.dependencies << 12)
            | (self.operand0 << 20)
            | (self.operand1 << 84)
        )


@dataclass(frozen=True)
class Command:
    request_id: int
    opcode: CommandOpcode
    graph: Tuple[GraphNode, ...] = ()
    priority: int = 0
    argument: int = 0
    flags: int = 0
    retry_count: int = 0


@dataclass(frozen=True)
class Completion:
    request_id: int
    status: Status
    result: int = 0


@dataclass(frozen=True)
class Fault:
    request_id: int
    address: int
    cause: Status
    engine: int = 1
    retry_count: int = 0
    replayable: bool = True

