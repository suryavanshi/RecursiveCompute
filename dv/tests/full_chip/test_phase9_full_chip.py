import json
import unittest
from pathlib import Path

from dv.phase9.invariants import (
    CrossCoverage,
    FullChipMonitor,
    VerificationError,
    exhaust_legal_backpressure,
    run_trace,
)


class FullChipTraceTest(unittest.TestCase):
    def test_agentic_descriptor_trace_drains(self) -> None:
        path = Path("sim/workloads/phase9_full_chip_trace.json")
        monitor, coverage = run_trace(json.loads(path.read_text(encoding="utf-8")))
        monitor.assert_drained()
        self.assertEqual(sum(coverage.hits.values()), 4)

    def test_required_cross_is_closed(self) -> None:
        coverage = CrossCoverage()
        for point in sorted(CrossCoverage.required_bins(), key=repr):
            coverage.sample(*point)
        coverage.close()
        self.assertEqual(len(coverage.hits), 1280)

    def test_legal_backpressure_state_space_has_progress(self) -> None:
        self.assertGreater(exhaust_legal_backpressure(), 8)


class CriticalInvariantNegativeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.monitor = FullChipMonitor(
            dma_windows={"a": (0x1000, 0x2000), "b": (0x2000, 0x3000)},
            node_partitions={0: "a", 1: "a", 2: "b"},
        )
        self.monitor.map_kv("a", 7, 0x1400)

    def test_cross_tenant_kv_access_is_rejected(self) -> None:
        with self.assertRaisesRegex(VerificationError, "cross-tenant"):
            self.monitor.read_kv("b", "a", 7)

    def test_dma_range_escape_is_rejected(self) -> None:
        with self.assertRaisesRegex(VerificationError, "outside permitted"):
            self.monitor.dma("a", 0x1ff0, 0x20)

    def test_unmatched_and_duplicate_completions_are_rejected(self) -> None:
        with self.assertRaisesRegex(VerificationError, "completion without"):
            self.monitor.complete("never-accepted")
        self.monitor.accept("once")
        self.monitor.complete("once")
        with self.assertRaisesRegex(VerificationError, "completion without"):
            self.monitor.complete("once")

    def test_refcount_underflow_is_rejected(self) -> None:
        self.monitor.release_kv("a", 7)
        with self.assertRaisesRegex(VerificationError, "underflow"):
            self.monitor.release_kv("a", 7)

    def test_early_scheduler_issue_is_rejected(self) -> None:
        with self.assertRaisesRegex(VerificationError, "before dependency"):
            self.monitor.issue(["dma-done"])

    def test_partition_escape_is_rejected(self) -> None:
        with self.assertRaisesRegex(VerificationError, "escaped"):
            self.monitor.route_collective(0, 2)


if __name__ == "__main__":
    unittest.main()
