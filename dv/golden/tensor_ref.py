"""Small dependency-free tensor reference helpers."""

from __future__ import annotations


def matmul(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    if not a or not b:
        return []
    inner = len(a[0])
    if any(len(row) != inner for row in a):
        raise ValueError("matrix a is ragged")
    if any(len(row) != len(b[0]) for row in b):
        raise ValueError("matrix b is ragged")
    if len(b) != inner:
        raise ValueError("matmul inner dimensions differ")

    cols = len(b[0])
    out: list[list[float]] = []
    for row in a:
        out_row = []
        for col in range(cols):
            out_row.append(sum(row[k] * b[k][col] for k in range(inner)))
        out.append(out_row)
    return out


def rms_norm(values: list[float], weights: list[float], eps: float = 1e-6) -> list[float]:
    if len(values) != len(weights):
        raise ValueError("values and weights lengths differ")
    mean_square = sum(item * item for item in values) / len(values)
    scale = 1.0 / ((mean_square + eps) ** 0.5)
    return [item * scale * weight for item, weight in zip(values, weights)]

