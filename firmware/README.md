# RCIF firmware

Phase 8 provides a freestanding RV64 control-plane firmware surface:

- `boot/` authenticates a versioned manifest through immutable ROM services,
  enforces anti-rollback, initializes all coherent queues, locks debug, and
  releases the engines only after authentication.
- `drivers/` contains queue, KV-fault recovery, and stable 64-bit telemetry
  helpers shared by firmware ports.
- `include/rcif_registers.h` is the C view of the frozen register map.

`start.S` and `linker.ld` are the minimal RV64 reset/link environment. The C
sources are intentionally platform-neutral and compile freestanding; a silicon
port supplies signature verification, OTP rollback services, interrupt setup,
and the physical allocator. The executable Phase 8 model in `runtime/driver/`
uses the same contract and covers boot, submission, fault replay, telemetry,
and security failure behavior in CI.
