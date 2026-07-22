# Tensor Verification Plan

## Scope and configuration

The target includes weight decode, scale application, MAC tiles, accumulator,
activation and normalization for the Phase 5 bounded array. Supported test
formats are INT4, FP4, FP8 and BF16 policy modes with documented saturation and
rounding behavior.

## Stimulus and checking

- Directed vectors hit zero, sign extremes, saturation, subnormal policy,
  group-scale boundaries, accumulator carry and unsupported configuration.
- Seeded random matrices compare against `dv/golden/tensor_ref.py`.
- Metamorphic tests cover zero weights, identity tiles and row permutation.
- The token-step scheduler regression exercises tensor nodes after dependent
  DMA and attention nodes.

## Assertions and coverage

- Unsupported formats fail without retirement as success.
- Scale group and packed weight lane never become misaligned.
- Accumulator behavior is deterministic and response data remains stable.
- Cross format, rows, activation, normalization, scale sign and saturation.

The bounded synthesizable array is closed by the format regression. Final
macro characterization and gate-level X/timing behavior are production-library
signoff dependencies.
