# Modal CPU Verilator Flow

The RTL flow runs Verilator on Modal CPU workers by default. Local Verilator is not required for normal development.

## Default Commands

```bash
make lint
make verilate
make sim
make regress
```

These commands dispatch to Modal:

- `make lint` runs Verilator lint remotely.
- `make verilate` builds the Verilator smoke binary remotely.
- `make sim` builds and runs the initial `rcif_top` smoke test remotely.
- `make regress` runs Python tests plus Verilator smoke remotely.

The first smoke test sends an echo command to `rcif_top` and checks the completion.

## Modal Executable

If the `modal` executable is not on PATH, set:

```bash
MODAL=/Users/kb/Library/Python/3.9/bin/modal make modal-regress
```

The Modal runner creates a Debian-based CPU image, installs Verilator and build tools, uploads the repository, and runs an internal `local-*` target in the container.

## Internal Local Targets

These are mainly for Modal and for debugging on a machine that already has Verilator installed:

```bash
make local-test
make local-lint
make local-verilate
make local-sim
make local-regress
```

## Design Intent

- Modal CPU workers are the default execution substrate for Verilator.
- Local machines do not need Verilator installed.
- Remote regressions use the same Makefile command contract as local debugging targets.
- UVM and formal flows will be added later; this flow is intentionally lightweight for the first RTL milestones.
