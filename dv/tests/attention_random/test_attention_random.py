import math
import random
import unittest

from dv.golden.attention_ref import rtl_online_attention


class RandomAttentionTest(unittest.TestCase):
    def test_random_outputs_are_bounded_and_page_order_independent(self) -> None:
        rng = random.Random(0x4A11)
        for _ in range(200):
            tokens = rng.randint(1, 32)
            query = [rng.randint(-3, 3) for _ in range(4)]
            keys = [[rng.randint(-3, 3) for _ in range(4)] for _ in range(tokens)]
            values = [[rng.randint(-100, 100) for _ in range(4)] for _ in range(tokens)]
            keep = [rng.choice([True, True, False]) for _ in range(tokens)]
            output = rtl_online_attention(query, keys, values, keep=keep)
            if any(keep):
                for dim, item in enumerate(output):
                    included = [value[dim] for value, kept in zip(values, keep) if kept]
                    self.assertGreaterEqual(item, min(included))
                    self.assertLessEqual(item, max(included))
            self.assertTrue(all(math.isfinite(item) for item in output))

    def test_extreme_score_distance_is_deterministic(self) -> None:
        output = rtl_online_attention(
            [127, 127, 127, 127],
            [[-128] * 4, [127] * 4],
            [[-100] * 4, [100] * 4],
        )
        self.assertEqual(output, [99, 99, 99, 99])


if __name__ == "__main__":
    unittest.main()
