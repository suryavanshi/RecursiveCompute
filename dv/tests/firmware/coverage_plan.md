# Phase 8 Firmware and Driver Coverage

The executable control-plane model covers authenticated boot, queue sizing and
backpressure, graph submission, dependency failure, KV miss allocation and
replay, telemetry saturation, image tampering, anti-rollback, and warm-reset
debug-lock retention. Freestanding C sources compile with warnings as errors.

Remaining Phase 9/10 work is instruction-accurate boot on a selected RISC-V
core, interrupt timing under concurrent engine traffic, IOMMU/coherency
integration, asymmetric production-signature acceleration, OTP provisioning,
and operating-system ioctl/pinning plumbing.
