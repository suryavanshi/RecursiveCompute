import unittest

from sim.event_model.rcif_sim import load_trace, simulate_trace


class EventModelTest(unittest.TestCase):
    def test_sample_trace_runs(self) -> None:
        trace = load_trace("sim/workloads/sample_agentic_coding_trace.json")
        result = simulate_trace(trace)
        self.assertEqual(result["summary"]["requests"], 2)
        self.assertGreater(result["summary"]["tpot_p95_s"], 0.0)
        self.assertGreater(result["summary"]["kv_bytes_read"], 0.0)


if __name__ == "__main__":
    unittest.main()

