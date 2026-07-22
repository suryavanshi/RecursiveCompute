import unittest

from dv.golden.attention_ref import rtl_online_attention


class DirectedAttentionTest(unittest.TestCase):
    def test_online_rescale(self) -> None:
        query = [1, 0, 0, 0]
        keys = [[0, 0, 0, 0], [2, 0, 0, 0], [1, 0, 0, 0]]
        values = [[8, 0, 0, 0], [24, 0, 0, 0], [16, 0, 0, 0]]
        self.assertEqual(rtl_online_attention(query, keys, values), [19, 0, 0, 0])

    def test_all_masked(self) -> None:
        self.assertEqual(
            rtl_online_attention([1], [[1], [2]], [[10], [20]], keep=[False, False]),
            [0],
        )


if __name__ == "__main__":
    unittest.main()
