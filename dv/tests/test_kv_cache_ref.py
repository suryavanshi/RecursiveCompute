import math
import unittest

from dv.golden.kv_cache_ref import PagedKVCache, attention_decode, build_debug_cache
from dv.golden.attention_ref import quantized_qk_dot
from dv.golden.tensor_ref import matmul, rms_norm


class PagedKVCacheTest(unittest.TestCase):
    def test_appends_across_pages(self) -> None:
        cache = build_debug_cache(tokens=5, page_tokens=2, num_kv_heads=2, head_dim=3)
        self.assertEqual(cache.tokens, 5)
        self.assertEqual(len(cache.pages), 3)
        key, value = cache.get_token(4)
        self.assertEqual(key[0][0], 0.5)
        self.assertEqual(value[1][0], 1.0)

    def test_attention_decode_shape(self) -> None:
        cache = build_debug_cache(tokens=4, page_tokens=2, num_kv_heads=1, head_dim=2)
        query = [[0.1, 0.2], [0.3, 0.4]]
        out = attention_decode(query, cache)
        self.assertEqual(len(out), 2)
        self.assertEqual(len(out[0]), 2)
        self.assertTrue(all(math.isfinite(item) for head in out for item in head))

    def test_attention_mask(self) -> None:
        cache = PagedKVCache(page_tokens=2, num_kv_heads=1, head_dim=1)
        cache.append([[1.0]], [[10.0]])
        cache.append([[1.0]], [[20.0]])
        out = attention_decode([[1.0]], cache, mask=[True, False])
        self.assertAlmostEqual(out[0][0], 10.0)


class TensorRefTest(unittest.TestCase):
    def test_matmul(self) -> None:
        self.assertEqual(matmul([[1.0, 2.0]], [[3.0], [4.0]]), [[11.0]])

    def test_rms_norm(self) -> None:
        out = rms_norm([1.0, 1.0], [2.0, 3.0], eps=0.0)
        self.assertEqual(out, [2.0, 3.0])


class AttentionTileRefTest(unittest.TestCase):
    def test_signed_int8_qk_dot(self) -> None:
        self.assertEqual(quantized_qk_dot([1, -2, 3, 4], [5, 6, -7, 8]), 4)

    def test_qk_dot_rejects_out_of_range(self) -> None:
        with self.assertRaises(ValueError):
            quantized_qk_dot([128], [1])


if __name__ == "__main__":
    unittest.main()
