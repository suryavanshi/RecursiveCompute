# RecursiveCompute
Use AI to build optimal Inference Compute systems

## Plans

- [Agentic LLM Inference ASIC Plan](docs/agentic_llm_inference_asic_plan.md)

## Initial Smoke Commands

Run the standard-library tests locally:

```bash
python3 -m unittest discover -s dv/tests -v
```

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
```
