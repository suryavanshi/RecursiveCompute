"""Pure-Python paged KV cache reference model.

This model is deliberately dependency-free so it can run in fresh sandboxes and
CI jobs before the project has a full ML stack. It provides correctness oracles
for page mapping and decode attention behavior.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import math
from typing import Iterable


Vector = list[float]
HeadValues = list[Vector]


@dataclass
class KVPage:
    page_id: int
    keys: list[HeadValues] = field(default_factory=list)
    values: list[HeadValues] = field(default_factory=list)

    @property
    def tokens(self) -> int:
        return len(self.keys)


@dataclass
class PagedKVCache:
    """Paged KV store for a single layer and sequence."""

    page_tokens: int
    num_kv_heads: int
    head_dim: int
    pages: list[KVPage] = field(default_factory=list)

    def __post_init__(self) -> None:
        if self.page_tokens <= 0:
            raise ValueError("page_tokens must be positive")
        if self.num_kv_heads <= 0:
            raise ValueError("num_kv_heads must be positive")
        if self.head_dim <= 0:
            raise ValueError("head_dim must be positive")

    @property
    def tokens(self) -> int:
        return sum(page.tokens for page in self.pages)

    def append(self, key: HeadValues, value: HeadValues) -> None:
        self._check_head_values(key, "key")
        self._check_head_values(value, "value")
        if not self.pages or self.pages[-1].tokens >= self.page_tokens:
            self.pages.append(KVPage(page_id=len(self.pages)))
        self.pages[-1].keys.append(copy_head_values(key))
        self.pages[-1].values.append(copy_head_values(value))

    def iter_tokens(self, limit: int | None = None) -> Iterable[tuple[HeadValues, HeadValues]]:
        emitted = 0
        for page in self.pages:
            for key, value in zip(page.keys, page.values):
                if limit is not None and emitted >= limit:
                    return
                yield key, value
                emitted += 1

    def get_token(self, token_index: int) -> tuple[HeadValues, HeadValues]:
        if token_index < 0 or token_index >= self.tokens:
            raise IndexError("token_index out of range")
        page_index = token_index // self.page_tokens
        offset = token_index % self.page_tokens
        page = self.pages[page_index]
        return page.keys[offset], page.values[offset]

    def _check_head_values(self, values: HeadValues, name: str) -> None:
        if len(values) != self.num_kv_heads:
            raise ValueError(f"{name} must contain {self.num_kv_heads} KV heads")
        for head in values:
            if len(head) != self.head_dim:
                raise ValueError(f"{name} head must contain {self.head_dim} elements")


def copy_head_values(values: HeadValues) -> HeadValues:
    return [[float(item) for item in head] for head in values]


def dot(a: Vector, b: Vector) -> float:
    if len(a) != len(b):
        raise ValueError("dot vector lengths differ")
    return sum(left * right for left, right in zip(a, b))


def stable_softmax(scores: list[float]) -> list[float]:
    if not scores:
        return []
    max_score = max(scores)
    exps = [math.exp(score - max_score) for score in scores]
    denom = sum(exps)
    return [item / denom for item in exps]


def attention_decode(
    query_heads: HeadValues,
    cache: PagedKVCache,
    *,
    context_tokens: int | None = None,
    mask: list[bool] | None = None,
) -> HeadValues:
    """Decode attention for one token over a paged KV cache.

    `query_heads` may contain more heads than the cache when using GQA/MQA. Query
    head `q` maps to KV head `floor(q * num_kv_heads / num_q_heads)`.
    """

    if not query_heads:
        raise ValueError("query_heads cannot be empty")
    for head in query_heads:
        if len(head) != cache.head_dim:
            raise ValueError("query head dimension does not match cache")

    total_context = cache.tokens if context_tokens is None else context_tokens
    if total_context < 0 or total_context > cache.tokens:
        raise ValueError("context_tokens out of range")
    if mask is not None and len(mask) < total_context:
        raise ValueError("mask shorter than context")

    outputs: HeadValues = []
    scale = 1.0 / math.sqrt(cache.head_dim)
    num_q_heads = len(query_heads)

    cached_tokens = list(cache.iter_tokens(limit=total_context))
    for q_index, query in enumerate(query_heads):
        kv_head = (q_index * cache.num_kv_heads) // num_q_heads
        scores: list[float] = []
        values: list[Vector] = []
        for token_index, (keys, token_values) in enumerate(cached_tokens):
            if mask is not None and not mask[token_index]:
                continue
            scores.append(dot(query, keys[kv_head]) * scale)
            values.append(token_values[kv_head])

        weights = stable_softmax(scores)
        output = [0.0 for _ in range(cache.head_dim)]
        for weight, value in zip(weights, values):
            for dim_index, item in enumerate(value):
                output[dim_index] += weight * item
        outputs.append(output)

    return outputs


def build_debug_cache(tokens: int, page_tokens: int, num_kv_heads: int, head_dim: int) -> PagedKVCache:
    """Build deterministic data for smoke tests and examples."""

    cache = PagedKVCache(page_tokens=page_tokens, num_kv_heads=num_kv_heads, head_dim=head_dim)
    for token in range(tokens):
        key: HeadValues = []
        value: HeadValues = []
        for head in range(num_kv_heads):
            key.append([float(token + head + dim + 1) / 10.0 for dim in range(head_dim)])
            value.append([float((token + 1) * (head + 1) + dim) / 10.0 for dim in range(head_dim)])
        cache.append(key, value)
    return cache

