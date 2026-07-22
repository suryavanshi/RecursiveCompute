"""Small dependency-free tensor reference helpers."""

from __future__ import annotations

import math


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


def decode_packed_weights(packed: int, fmt: str, zero_point: int, lanes: int = 4) -> list[int]:
    """Decode the signed INT8/INT4 formats consumed by Phase 5 RTL."""
    if fmt not in {"int8", "int4"}:
        raise ValueError("unsupported weight format")
    if not -128 <= zero_point <= 127:
        raise ValueError("zero_point must fit signed int8")
    bits = 8 if fmt == "int8" else 4
    sign = 1 << (bits - 1)
    mask = (1 << bits) - 1
    result = []
    for lane in range(lanes):
        raw = (packed >> (lane * bits)) & mask
        signed = raw - (1 << bits) if raw & sign else raw
        result.append(signed - zero_point)
    return result


def round_q8_8(product: int) -> int:
    """Round a signed Q8.8 product to nearest, with ties away from zero."""
    return (product + (128 if product >= 0 else 127)) // 256


def saturate_int16(value: int) -> tuple[int, bool]:
    clipped = max(-32768, min(32767, value))
    return clipped, clipped != value


def quantized_gemv(
    activation: list[int],
    packed_rows: list[int],
    formats: list[str],
    zero_points: list[int],
    scales_q8_8: list[int],
    biases: list[int],
    *,
    activation_mode: str = "bypass",
) -> tuple[list[int], list[bool]]:
    """Bit-exact reference for the four-row tensor-array datapath."""
    rows = len(packed_rows)
    if not all(len(items) == rows for items in (formats, zero_points, scales_q8_8, biases)):
        raise ValueError("row metadata lengths differ")
    if any(not -128 <= item <= 127 for item in activation):
        raise ValueError("activations must fit signed int8")
    if activation_mode not in {"bypass", "relu", "clamp_int8"}:
        raise ValueError("unsupported activation mode")
    outputs: list[int] = []
    saturated: list[bool] = []
    for packed, fmt, zero_point, scale, bias in zip(
        packed_rows, formats, zero_points, scales_q8_8, biases
    ):
        weights = decode_packed_weights(packed, fmt, zero_point, len(activation))
        accumulator = sum(left * right for left, right in zip(activation, weights))
        value, did_saturate = saturate_int16(round_q8_8(accumulator * scale) + bias)
        if activation_mode == "relu":
            value = max(0, value)
        elif activation_mode == "clamp_int8":
            value = max(-128, min(127, value))
        outputs.append(value)
        saturated.append(did_saturate)
    return outputs, saturated


def integer_rms_norm(
    values: list[int], gains_q8_8: list[int], epsilon: int = 0
) -> tuple[list[int], list[bool]]:
    """Bit-exact integer RMSNorm used by the optional tensor post-process."""
    if not values or len(values) != len(gains_q8_8):
        raise ValueError("values and gains must be non-empty and equal length")
    rms = math.isqrt(sum(item * item for item in values) // len(values) + epsilon)
    if rms == 0:
        return [0] * len(values), [False] * len(values)
    outputs = []
    saturated = []
    for value, gain in zip(values, gains_q8_8):
        numerator = value * gain
        normalized = abs(numerator) // rms
        if numerator < 0:
            normalized = -normalized
        item, clipped = saturate_int16(normalized)
        outputs.append(item)
        saturated.append(clipped)
    return outputs, saturated
