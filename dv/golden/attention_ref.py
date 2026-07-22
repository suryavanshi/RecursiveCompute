"""Attention reference entry points."""

from __future__ import annotations

from .kv_cache_ref import HeadValues, PagedKVCache, attention_decode


def decode_attention(query_heads: HeadValues, cache: PagedKVCache) -> HeadValues:
    return attention_decode(query_heads, cache)


def quantized_qk_dot(query: list[int], key: list[int]) -> int:
    """Return the exact signed-int8 QK dot product used by the first RTL tile."""
    if len(query) != len(key):
        raise ValueError("query and key lengths differ")
    if any(value < -128 or value > 127 for value in query + key):
        raise ValueError("QK elements must fit signed int8")
    return sum(query_value * key_value for query_value, key_value in zip(query, key))


def rtl_online_attention(
    query: list[int],
    keys: list[list[int]],
    values: list[list[int]],
    *,
    keep: list[bool] | None = None,
    weight_bits: int = 16,
) -> list[int]:
    """Bit-exact model of the first synthesizable online-softmax RTL.

    Scores are exact signed-int8 dot products.  A score distance ``d`` receives
    the power-of-two weight ``2**-(min(d, weight_bits - 1))`` in Q1.15.  This
    keeps the datapath deterministic and divider/LUT free while the production
    exponential approximation is still being selected.
    """
    if len(keys) != len(values):
        raise ValueError("keys and values differ in length")
    if not values:
        return [0 for _ in query]
    if any(len(item) != len(query) for item in keys + values):
        raise ValueError("all vectors must match the query length")
    if keep is None:
        keep = [True] * len(keys)
    if len(keep) != len(keys):
        raise ValueError("mask length differs from token count")

    one = 1 << (weight_bits - 1)
    maximum: int | None = None
    denominator = 0
    accumulator = [0 for _ in query]
    for key, value, include in zip(keys, values, keep):
        if not include:
            continue
        score = quantized_qk_dot(query, key)
        if maximum is None:
            maximum = score
            denominator = one
            accumulator = [item * one for item in value]
        elif score > maximum:
            weight = one >> min(score - maximum, weight_bits - 1)
            denominator = ((denominator * weight) >> (weight_bits - 1)) + one
            accumulator = [
                ((total * weight) >> (weight_bits - 1)) + item * one
                for total, item in zip(accumulator, value)
            ]
            maximum = score
        else:
            weight = one >> min(maximum - score, weight_bits - 1)
            denominator += weight
            accumulator = [total + item * weight for total, item in zip(accumulator, value)]
    if maximum is None:
        return [0 for _ in query]
    return [int(total / denominator) for total in accumulator]
