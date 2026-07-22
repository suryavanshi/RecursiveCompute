# Numerics

The first implementation uses simple deterministic numeric behavior so the simulator, golden model, and RTL can converge before production quantization work begins.

## Initial Modes

| Mode | Purpose |
| --- | --- |
| `fp32_debug` | Golden-model correctness and early RTL tolerance checks. |
| `bf16_reference` | Later reference path for hardware with BF16 support. |
| `int8_kv` | First KV compression target. |
| `int8_qk_debug` | Exact four-lane signed Q·K RTL bring-up path. |
| `int4_weight` | First weight compression target. |

## Rules

- Golden references use Python `float`, treated as FP64 software math but compared with explicit tolerances.
- RTL tests must define tolerance per operation and per numeric mode.
- Quantized formats must specify scale granularity, rounding, saturation, zero point handling, and accumulation width before RTL implementation.
- Page metadata must carry KV format tags so attention never guesses how to decode a page.

The first Q·K tile consumes four packed signed-int8 query elements in payload
bits `[31:0]` and four signed-int8 key elements in `[63:32]`. Products and the
sum are exact signed 32-bit integers. This is a verification stepping stone;
production attention will add scaling and higher-precision online softmax.

## Phase 4 Online Attention Prototype

The bounded streaming engine uses signed-int8 Q, K, and V vectors with four
elements per head. Q·K scores accumulate exactly into signed 32 bits. The
online softmax stores the current maximum, a 48-bit unsigned denominator, and
four signed 48-bit weighted-value accumulators.

For a score distance `d >= 0`, the prototype weight is
`2^(-min(d, 15))` represented as Q1.15 (`0x8000 >> min(d, 15)`). When a new
maximum arrives, the previous denominator and accumulators are rescaled before
the new V vector is added. Final signed-int16 context elements use truncating
signed division toward zero. An all-masked request returns zero and asserts the
`all_masked` response bit.

This power-of-two approximation is synthesizable and bit-exact against
`rtl_online_attention` in `dv/golden/attention_ref.py`; it is not the final
quality-mode exponential. Selecting a production LUT/polynomial and defining
its error tolerance remains part of numeric-mode closure.

## Phase 5 Tensor Prototype

The first tensor array is a four-input by four-output GEMV slice. Activations
are signed INT8. Each programmed output row independently selects signed INT8
weights (four bytes) or packed signed INT4 weights (four low nibbles). Both
formats sign-extend before subtracting a signed INT8 zero point, producing a
signed nine-bit decoded weight. Four products accumulate exactly in signed 32
bits.

Each row applies a signed Q8.8 scale and signed 32-bit bias:

```text
scaled = round_away_from_zero(accumulator * scale_q8_8 / 256) + bias
```

Half ties round away from zero and exact negative integers remain exact. The
result saturates to signed INT16 before activation. Supported activations are
bypass, ReLU, and an INT8 clamp. Saturation is reported per output row and is
not cleared by a later activation clamp.

Optional integer RMSNorm computes `floor(sqrt(mean(x*x) + epsilon))` and emits
`x * gain_q8_8 / rms`, truncated toward zero and saturated to signed INT16.
Consequently RMSNorm output represents a Q8.8 normalized value when gain is
`256`. A zero RMS denominator produces zero without division.

`quantized_gemv` and `integer_rms_norm` in `dv/golden/tensor_ref.py` are the
bit-exact reference. FP8, FP4, MX formats, groupwise scale fetch, and a
higher-precision production RMSNorm remain future numeric modes.
