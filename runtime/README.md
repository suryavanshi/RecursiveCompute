# Runtime

`runtime/driver/` is the Phase 8 host-driver prototype. It probes an
authenticated device, submits bounded token graphs and KV translations through
the coherent command ring, drains completions, services firmware interrupts,
and reads validated telemetry counters. The deterministic device model makes
the firmware/driver ABI executable without a RISC-V ISS; it is a contract model,
not a performance model or replacement for the RTL scheduler.

The Phase 10 backend in `fpga/prototype.py` implements the same `RcifDevice`
boundary, so `RcifDriver` submits unchanged graph descriptors to either the
control-plane model or the reduced FPGA/emulation datapath.
