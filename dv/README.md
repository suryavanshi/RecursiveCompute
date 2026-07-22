# Design Verification

Verification collateral lives here: golden models, formal properties, directed
tests, random tests, and coverage plans. `dv/tests/collectives/` contains the
Phase 7 exhaustive credit-state check and four-node Verilator regression.
`dv/tests/firmware/` covers the Phase 8 authenticated boot, coherent queue,
fault-replay, telemetry, and host-driver contract.

Phase 9 adds `dv/phase9/` independent safety monitors and
`dv/tests/full_chip/` trace-driven, negative-invariant, cross-coverage, reset,
backpressure, and randomized top-level tests. Run `make phase9` remotely or
`make local-phase9` with a local Verilator installation.
