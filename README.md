# RecursiveCompute
Use AI to build optimal Inference Compute systems

## Plans

- [Agentic LLM Inference ASIC Plan](docs/agentic_llm_inference_asic_plan.md)

## Initial Smoke Commands

Run the standard-library tests locally:

```bash
python3 -m unittest discover -s dv/tests -v
```

This includes the Phase 8 firmware/driver suite: freestanding C compilation,
MMIO boot simulation, secure-boot negative paths, graph submission, KV fault
replay, and telemetry validation.

Run the first event-model simulation:

```bash
python3 -m sim.event_model.rcif_sim sim/workloads/sample_agentic_coding_trace.json --pretty
```

Generate a synthetic agentic coding trace:

```bash
python3 -m sim.tracegen.generate_agentic_trace \
  --requests 4 \
  --prefix-tokens 131072 \
  --reuse-ratio 0.9 \
  --output /tmp/generated_agentic_trace.json
```

## RTL Simulation

Verilator lint/build/simulation runs on Modal CPU workers by default. Local Verilator is not required.

```bash
make lint
make verilate
make sim
make regress
make phase9
make phase10
```

If `modal` is not on PATH:

```bash
MODAL=/Users/kb/Library/Python/3.9/bin/modal make regress
```

The `local-*` targets are only for debugging on machines that already have Verilator installed:

```bash
make local-lint
make local-sim
make local-regress
make local-phase9
```

`phase9` adds assertion-enabled full-chip directed and randomized simulation,
security/memory-safety invariant tests, real descriptor-trace replay, exhaustive
cross coverage, reset/backpressure stress, and an enforced Verilator coverage
report. See [the full-chip verification plan](docs/verification/full_chip_vplan.md)
for bounded scope and physical-signoff gates.

`phase10` adds the reduced FPGA shell, an AXI external-DDR proxy, real runtime
token-graph submission, a bit-exact toy attention/GEMV block, synthetic agentic
trace replay, KV page-fault migration, and a 5% cycle-model agreement gate. See
[the FPGA prototype guide](fpga/README.md) for the reproducible emulation scope
and the physical-board closure requirements.
