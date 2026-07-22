import dataclasses
import pathlib
import subprocess
import tempfile
import unittest

from runtime.driver import (
    FirmwareController,
    FirmwareImage,
    GraphNode,
    RcifDevice,
    RcifDriver,
    Status,
)
from runtime.driver.protocol import Counter, DeviceStatus, GraphOpcode


ROOT_KEY = bytes.fromhex("00112233445566778899aabbccddeeff")


class Phase8FirmwareDriverTest(unittest.TestCase):
    def setUp(self):
        self.device = RcifDevice(otp_minimum_version=3)
        self.firmware = FirmwareController(self.device, ROOT_KEY, queue_entries=8)
        self.image = FirmwareImage.sign(b"phase-8-rv64-firmware", 3, ROOT_KEY)
        self.assertTrue(self.firmware.boot(self.image))
        self.driver = RcifDriver(self.device, self.firmware)
        self.driver.probe()

    def test_firmware_boot_initializes_queues_and_locks_debug(self):
        self.assertEqual(self.device.status, DeviceStatus.RUNNING)
        self.assertTrue(self.device.secure_verified)
        self.assertTrue(self.device.debug_locked)
        self.assertEqual(self.device.firmware_version, 3)
        self.assertEqual(self.device.command_ring.entries, 8)
        self.assertEqual(self.driver.read_counter(Counter.BOOT_ATTEMPTS), 1)

    def test_host_submits_descriptor_graph(self):
        graph = (
            GraphNode(GraphOpcode.NOP, node_id=0, operand0=0x1234),
            GraphNode(GraphOpcode.NOP, node_id=1, dependencies=1, operand0=0x00FF),
            GraphNode(
                GraphOpcode.COMPLETE,
                node_id=2,
                dependencies=3,
                operand0=0xA000,
            ),
        )
        request_id = self.driver.submit_graph(graph, priority=3)
        completion = self.driver.wait(request_id)
        self.assertEqual(completion.status, Status.OK)
        self.assertEqual(completion.result, 0x1234 ^ 0x00FF ^ 0xA000)
        self.assertEqual(self.driver.read_counter(Counter.ACCEPTED), 1)
        self.assertEqual(self.driver.read_counter(Counter.COMPLETED), 1)
        self.assertEqual(self.driver.read_counter(Counter.GRAPH_NODES), 3)

    def test_dependency_deadlock_is_reported(self):
        request_id = self.driver.submit_graph(
            (
                GraphNode(GraphOpcode.NOP, node_id=0, dependencies=2),
                GraphNode(GraphOpcode.COMPLETE, node_id=1, dependencies=1),
            )
        )
        completion = self.driver.wait(request_id)
        self.assertEqual(completion.status, Status.GRAPH_DEADLOCK)
        self.assertEqual(self.driver.read_counter(Counter.ERRORS), 1)

    def test_kv_fault_is_mapped_and_replayed_without_reset(self):
        request_id = self.driver.translate_kv(0xFEED)
        completion = self.driver.wait(request_id)
        self.assertEqual(completion.status, Status.OK)
        self.assertEqual(completion.result, 0x1000)
        self.assertEqual(self.device.status, DeviceStatus.RUNNING)
        self.assertEqual(self.driver.read_counter(Counter.KV_FAULTS), 1)
        self.assertEqual(self.driver.read_counter(Counter.KV_RECOVERED), 1)

        second = self.driver.translate_kv(0xFEED)
        self.assertEqual(self.driver.wait(second).result, 0x1000)
        self.assertEqual(self.driver.read_counter(Counter.KV_FAULTS), 1)

    def test_counter_reads_are_64_bit_and_saturating(self):
        self.device.counters[Counter.ACCEPTED] = (1 << 64) - 2
        first = self.driver.submit_graph(
            (GraphNode(GraphOpcode.COMPLETE, node_id=0, operand0=1),)
        )
        second = self.driver.submit_graph(
            (GraphNode(GraphOpcode.COMPLETE, node_id=0, operand0=2),)
        )
        self.driver.wait(first)
        self.driver.wait(second)
        self.assertEqual(self.driver.read_counter(Counter.ACCEPTED), (1 << 64) - 1)

    def test_command_ring_backpressure_is_visible(self):
        graph = (GraphNode(GraphOpcode.COMPLETE, node_id=0),)
        for _ in range(8):
            self.driver.submit_graph(graph)
        with self.assertRaises(BlockingIOError):
            self.driver.submit_graph(graph)
        self.assertEqual(self.driver.read_counter(Counter.QUEUE_ERRORS), 1)


class Phase8SecureBootTest(unittest.TestCase):
    def test_tamper_and_rollback_never_enable_queues(self):
        device = RcifDevice(otp_minimum_version=4)
        firmware = FirmwareController(device, ROOT_KEY)
        valid = FirmwareImage.sign(b"firmware", 4, ROOT_KEY)
        tampered = dataclasses.replace(valid, payload=b"tampered")
        self.assertFalse(firmware.boot(tampered))
        self.assertEqual(device.status, DeviceStatus.FATAL)
        self.assertFalse(device.enabled)
        self.assertEqual(device.read_counter(Counter.BOOT_FAILURES), 1)

        device.power_on_reset()
        rollback = FirmwareImage.sign(b"old", 3, ROOT_KEY)
        self.assertFalse(firmware.boot(rollback))
        self.assertFalse(device.enabled)

    def test_debug_lock_survives_warm_reset(self):
        device = RcifDevice()
        firmware = FirmwareController(device, ROOT_KEY)
        self.assertTrue(firmware.boot(FirmwareImage.sign(b"fw", 1, ROOT_KEY)))
        device.warm_reset()
        self.assertTrue(device.debug_locked)
        self.assertFalse(device.enabled)


class Phase8FreestandingCTest(unittest.TestCase):
    def test_firmware_c_sources_compile_freestanding(self):
        repo = pathlib.Path(__file__).resolve().parents[3]
        sources = (
            repo / "firmware/boot/rcif_boot.c",
            repo / "firmware/drivers/rcif_queue.c",
            repo / "firmware/drivers/rcif_kv_fault.c",
            repo / "firmware/drivers/rcif_telemetry.c",
        )
        for source in sources:
            subprocess.run(
                [
                    "clang",
                    "-std=c11",
                    "-ffreestanding",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-fsyntax-only",
                    str(source),
                ],
                cwd=repo,
                check=True,
                capture_output=True,
                text=True,
            )

    def test_c_firmware_boots_in_mmio_simulation(self):
        repo = pathlib.Path(__file__).resolve().parents[3]
        with tempfile.TemporaryDirectory() as directory:
            executable = pathlib.Path(directory) / "rcif_firmware_boot_test"
            subprocess.run(
                [
                    "clang",
                    "-std=c11",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-I",
                    str(repo),
                    str(repo / "dv/tests/firmware/rcif_firmware_boot_test.c"),
                    str(repo / "firmware/boot/rcif_boot.c"),
                    str(repo / "firmware/drivers/rcif_queue.c"),
                    str(repo / "firmware/drivers/rcif_kv_fault.c"),
                    "-o",
                    str(executable),
                ],
                cwd=repo,
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    unittest.main()
