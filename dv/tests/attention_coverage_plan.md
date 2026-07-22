# Streaming Attention Coverage Plan

The Phase 4 prototype is a bounded signed-int8 decode-attention engine with a
four-element head dimension. The standalone Verilator test and Python golden
tests cover the functional contract below. Production formats and larger head
dimensions will reuse the same ready/valid boundaries.

| Area | Current bins | Test source |
| --- | --- | --- |
| Sequence length | zero/all-masked, partial page, cross-page | directed RTL, randomized Python |
| Page order | identity, non-contiguous logical-to-physical map | directed RTL |
| Head mode | MHA-compatible 1:1, GQA 4:2, MQA 4:1 | directed RTL |
| Mask | none, explicit keep/drop, sliding window, attention sink, all masked | directed RTL and Python |
| Score range | equal, increasing/rescale, negative, saturated distance | directed and randomized Python |
| Backpressure | response held for four cycles; payload stability checked | directed RTL |
| Throughput | one kept KV token accepted per cycle after pipeline fill; total latency bounded by `context + 12` cycles | directed RTL |
| Format | signed-int8 Q/K/V, signed 32-bit dot, Q1.15 power-of-two softmax weight, signed-int16 output | directed RTL and bit-exact Python |

Future coverage must add page-reader request stalls, randomized RTL vectors,
format-tag rejection, production exponential approximation error, head
dimensions 64 through 256, and direct coupling to the Phase 3 MMU/DMA path.
