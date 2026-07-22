import json
import unittest
from pathlib import Path

from dv.golden.attention_ref import rtl_online_attention
from dv.golden.tensor_ref import quantized_gemv
from fpga.prototype import DEFAULT_TOY_MODEL, FpgaPrototypeDevice, build_toy_graph, run_agentic_trace
from runtime.driver import FirmwareController, FirmwareImage, RcifDriver, Status
from runtime.driver.protocol import Counter


ROOT_KEY = bytes.fromhex("102132435465768798a9bacbdcedfe0f")


class Phase10FpgaPrototypeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.device = FpgaPrototypeDevice(local_pages=2)
        firmware = FirmwareController(self.device, ROOT_KEY, queue_entries=16)
        image = FirmwareImage.sign(b"phase-10-fpga-firmware", 1, ROOT_KEY)
        self.assertTrue(firmware.boot(image))
        self.driver = RcifDriver(self.device, firmware)
        self.driver.probe()

    def test_real_token_graph_is_numerically_exact(self) -> None:
        request_id = self.driver.submit_graph(build_toy_graph(), priority=3)
        completion = self.driver.wait(request_id)
        self.assertEqual(completion.status, Status.OK)

        attention = rtl_online_attention(
            list(DEFAULT_TOY_MODEL.query),
            [list(item) for item in DEFAULT_TOY_MODEL.keys],
            [list(item) for item in DEFAULT_TOY_MODEL.values],
        )
        expected, _ = quantized_gemv(
            attention,
            list(DEFAULT_TOY_MODEL.packed_rows),
            ["int8"] * 4,
            [0] * 4,
            list(DEFAULT_TOY_MODEL.scales_q8_8),
            list(DEFAULT_TOY_MODEL.biases),
        )
        self.assertEqual(self.device.outputs[request_id], tuple(expected))
        self.assertNotEqual(completion.result, 0)
        self.assertEqual(self.driver.read_counter(Counter.GRAPH_NODES), 4)

    def test_fault_migration_and_replay_do_not_reset_device(self) -> None:
        first = self.driver.submit_graph(build_toy_graph())
        self.assertEqual(self.driver.wait(first).status, Status.OK)
        first_record = self.device.records[first]
        self.assertEqual(first_record.page_faults, 1)
        self.assertEqual(first_record.migrations, 1)
        self.assertEqual(self.driver.read_counter(Counter.KV_FAULTS), 1)
        self.assertEqual(self.driver.read_counter(Counter.KV_RECOVERED), 1)

        self.device.migrate_to_host(1)
        second = self.driver.submit_graph(build_toy_graph())
        self.assertEqual(self.driver.wait(second).status, Status.OK)
        self.assertEqual(self.device.records[second].page_faults, 1)
        self.assertEqual(self.device.records[second].migrations, 1)
        self.assertEqual(self.driver.read_counter(Counter.KV_FAULTS), 2)
        self.assertEqual(self.driver.read_counter(Counter.KV_RECOVERED), 2)
        self.assertTrue(self.device.enabled)
        self.assertEqual(self.device.outputs[first], self.device.outputs[second])

    def test_measured_cycles_match_independent_event_prediction(self) -> None:
        request_id = self.driver.submit_graph(build_toy_graph())
        self.driver.wait(request_id)
        record = self.device.records[request_id]
        error = abs(record.cycles - record.predicted_cycles) / record.predicted_cycles
        self.assertLessEqual(error, 0.05)

    def test_synthetic_agentic_trace_uses_runtime_path(self) -> None:
        trace = json.loads(
            Path("sim/workloads/phase10_fpga_trace.json").read_text(encoding="utf-8")
        )
        report = run_agentic_trace(self.driver, self.device, trace)
        self.assertEqual(report.graphs, 8)
        self.assertLessEqual(report.relative_error, report.tolerance)
        self.assertEqual(self.driver.read_counter(Counter.ACCEPTED), 8)
        self.assertEqual(self.driver.read_counter(Counter.COMPLETED), 8)


if __name__ == "__main__":
    unittest.main()
