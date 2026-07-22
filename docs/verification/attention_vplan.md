# Attention Verification Plan

## Scope and configuration

The target is the bounded streaming attention path: four signed INT8 lanes,
up to 32 context tokens, online softmax, causal/sliding/sink/sparse masks and
four-lane value reduction. Wider production formats use the same contracts but
require regenerated arithmetic vectors.

## Stimulus and checking

- Directed vectors cover signed QK arithmetic, all-masked input, extreme score
  separation, rounding ties and non-contiguous page order.
- Seeded random tests compare every output with `dv/golden/attention_ref.py`.
- Metamorphic checks permute pages, shift all logits and bound each result by
  the included value extrema.
- Full-chip smoke issues the QK command through command queue and scheduler.

## Assertions and coverage

- Masked tokens never contribute; outputs and internal normalization remain
  finite; response data is stable while stalled.
- Cross token count, mask mode, page size, precision, score class and fault.
- Numerical tolerance and rounding are defined by `docs/specs/numerics.md`.

The executable bounded format is closed by directed/random RTL and golden-model
tests. FP4/FP8 hardened arithmetic macro validation remains a technology
signoff gate rather than a waiver of the architectural behavior.
