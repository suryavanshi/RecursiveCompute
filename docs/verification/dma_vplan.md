# DMA Verification Plan

## Scope and configuration

The target includes descriptor fetch, direct copy, indirect gather, index RAM,
range validation, deterministic page contents and injected ECC errors. The
bounded memory contains 256 pages and the descriptor FIFO contains four items.

## Stimulus and checking

- Directed RTL covers zero length, reserved bits, source/destination overflow,
  chained copies, sparse gather, missing index and poisoned source data.
- Random transactions vary length, alignment, direct/indirect mode, queue
  pressure, tenant aperture and retry/fault class.
- The scoreboard checks every copied page and checksum without relying on the
  implementation's internal RAM.
- Full-chip traffic holds completions for randomized intervals and resets only
  at command boundaries; gate/reset signoff later adds library timing.

## Assertions and coverage

- No read or write may extend beyond the configured physical aperture.
- Descriptor and response payloads remain stable under backpressure.
- ECC poison must be reported before destination modification.
- Cross length class, boundary class, direct/gather, priority and fault type.

`dv/tests/full_chip/test_phase9_full_chip.py` supplies negative aperture tests;
the top-level Verilator tests exercise range and ECC status end to end. The
bounded scope is closed. IOMMU/PASID and production AXI protocol checking are
open platform integration items.
