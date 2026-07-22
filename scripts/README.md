# Scripts

`run_verilator.sh` provides local lint and directed simulations. In addition to
the top-level smoke, `attention`, `tensor`, and `scheduler` select the standalone
Phase 4, Phase 5, and Phase 6 engine regressions.
`scripts/run_verilator.sh collectives` builds and runs the Phase 7 four-node
collective-engine test, including ring/tree AllReduce, MoE AllToAll, retry, and
partition-containment scenarios. It also runs the standalone credit FIFO and
the distributed four-chip ring simulation under receiver backpressure.

`scripts/run_verilator.sh phase9` builds the top with assertions and coverage,
runs directed plus 1,024-command randomized full-chip simulations, merges LCOV
data, and enforces the 90% line-coverage threshold. The `make phase9` wrapper
runs the same flow on Modal; `make local-phase9` uses a local Verilator.

`scripts/run_verilator.sh fpga-lint` elaborates the complete reduced Phase 10
FPGA shell, including the token scheduler and AXI external-memory reader.
`scripts/run_verilator.sh fpga` also simulates DDR burst length, downstream
backpressure, response forwarding, and return to idle.
