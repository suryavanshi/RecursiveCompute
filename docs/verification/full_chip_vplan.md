# Full-Chip Verification Plan

## Executable stack

`make phase9` runs standard-library unit/model tests plus the assertion-enabled
full-chip Verilator suite. The suite combines the long directed smoke test with
1,024 deterministic randomized commands, randomized completion backpressure,
multiple reset lengths, coverage collection and a 90% executable line-coverage
gate. Block regressions remain part of `local-regress`.

The trace `sim/workloads/phase9_full_chip_trace.json` represents one reused-KV
agentic token flow across KV mapping, DMA, dependency scheduling and a local
collective. `dv/phase9/invariants.py` independently checks command/completion
conservation, tenant KV isolation, DMA apertures, refcounts, dependency issue,
partition routing and the complete 1,280-bin required cross.

## Critical assertions

| Contract | Executable checker |
| --- | --- |
| No cross-tenant KV access | `FullChipMonitor.read_kv` negative test |
| No DMA outside range | RTL directed test plus monitor negative test |
| Exactly one completion per accept | `rcif_top_assertions` and scoreboard |
| No refcount underflow | monitor negative test |
| Dependencies ready before issue | scheduler RTL/test and monitor |
| No collective partition escape | monitor negative test |
| No deadlock under legal backpressure | exhaustive model and random RTL stalls |

## Coverage and signoff

- Functional: all required cross bins must be hit; no missing bin is waived.
- Code: bounded open-source RTL line coverage is at least 90%. Production
  interfaces and macros are added to the denominator when they exist;
  exclusions are recorded in `coverage_waivers.md`.
- Assertions: every critical contract has a positive or negative executable
  test. RTL-port omissions are tracked, not silently treated as proven.
- Seeds: deterministic default seed is mandatory in CI; additional seeds may
  be layered without changing the reference result.

## Reset, CDC/RDC and gate flow

Current RTL has one clock and one asynchronous active-low reset. Lint plus
random reset sequences close the bounded single-domain scope. Actual gate-level
SDF simulation, scan reset, memory macro timing, CDC/RDC reports and X-prop are
hard signoff gates once a standard-cell/memory library and synthesized netlist
exist. They are not claimed by the RTL surrogate.

The bounded Phase 9 implementation is complete when `make phase9` and
`make local-regress` pass with no assertion or coverage failure. Tapeout-grade
signoff remains conditional on closing the explicit production-library gates.
