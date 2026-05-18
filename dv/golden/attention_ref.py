"""Attention reference entry points."""

from __future__ import annotations

from .kv_cache_ref import HeadValues, PagedKVCache, attention_decode


def decode_attention(query_heads: HeadValues, cache: PagedKVCache) -> HeadValues:
    return attention_decode(query_heads, cache)

