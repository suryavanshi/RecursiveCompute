# Tensor Format Coverage Plan

The Phase 5 tensor prototype is a four-input by four-output GEMV engine. Its
programming port models DMA delivery of one packed weight row and associated
quantization metadata while idle.

| Area | Current bins | Verification |
| --- | --- | --- |
| Weight format | signed INT8, packed signed INT4, unsupported format | Python and directed RTL |
| Quantization | zero point negative/zero/positive; Q8.8 scale negative/zero/positive | seeded Python and directed RTL |
| Accumulation | mixed-sign exact 32-bit dot products | directed RTL |
| Rounding | positive/negative half ties and exact negative integers | Python |
| Saturation | no saturation, positive and negative INT16 saturation | Python and directed RTL |
| Activation | bypass, ReLU, INT8 clamp, invalid mode | Python and directed RTL |
| RMSNorm | nonzero vector, zero-safe denominator, per-lane Q8.8 gain | Python and directed RTL |
| Configuration | all rows loaded, invalid stored format | directed RTL |
| Backpressure | result and metadata held stable for five cycles | directed RTL |

Future format closure must add FP8/FP4/MX encodings, groupwise scale fetch,
randomized RTL vectors, accumulator overflow injection, production RMSNorm
precision, and DMA transaction-level coupling.
