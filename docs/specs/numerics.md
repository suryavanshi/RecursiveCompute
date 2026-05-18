# Numerics

The first implementation uses simple deterministic numeric behavior so the simulator, golden model, and RTL can converge before production quantization work begins.

## Initial Modes

| Mode | Purpose |
| --- | --- |
| `fp32_debug` | Golden-model correctness and early RTL tolerance checks. |
| `bf16_reference` | Later reference path for hardware with BF16 support. |
| `int8_kv` | First KV compression target. |
| `int4_weight` | First weight compression target. |

## Rules

- Golden references use Python `float`, treated as FP64 software math but compared with explicit tolerances.
- RTL tests must define tolerance per operation and per numeric mode.
- Quantized formats must specify scale granularity, rounding, saturation, zero point handling, and accumulation width before RTL implementation.
- Page metadata must carry KV format tags so attention never guesses how to decode a page.

