# FPGA/Emulation Prototype Contract

## Scope

Phase 10 maps the reduced D-chip datapath into a board-neutral FPGA shell. The
mapped logic is the frozen token-graph descriptor SRAM and scheduler, DMA,
paged attention, four-lane tensor array, completion FIFO, and an AXI4 external
memory read boundary. Vendor PCIe, DDR/HBM controller, clocking, reset, and pin
IP remain board overlays rather than portable RTL.

The pre-board emulator implements the same `RcifDevice` contract used by the
Phase 8 firmware and driver. It is a cycle-accounted functional prototype, not
a replacement for post-route timing or physical memory measurements.

## External-memory model

The default profile is a 100 MHz FPGA fabric with a 128-bit local-DRAM beat.
Local reads cost 12 cycles. A host-tier fault and migration costs 24 setup
cycles, 80 source latency cycles, and one cycle per 16 transferred bytes. Local
capacity is bounded in pages; deterministic lowest-virtual-page eviction makes
replay stable.

The synthesizable AXI reader converts a nonzero address/beat request to one
AXI4 burst, preserves downstream backpressure, forwards the AXI response error,
and returns to idle only after the accepted `RLAST` beat.

## Acceptance workload

`sim/workloads/phase10_fpga_trace.json` contains two synthetic coding turns and
eight output tokens. Each token is an actual four-node frozen descriptor graph:

1. DMA/prefetch a virtual KV page into local memory.
2. Run four-token signed-INT8 online attention.
3. Feed the attention result into a four-row INT8 projection.
4. Complete with a deterministic signature and retain the numeric vector.

Attention and projection outputs must match the independent Python golden
models exactly. The first graph faults and migrates its KV page; a directed test
evicts it to the host tier and proves a second fault/migration completes without
device reset and with validated telemetry.

## Timing agreement

The agreed pre-board tolerance is 5% relative error between measured emulation
cycles and the analytical operation/memory event prediction. The acceptance
trace currently measures 662 cycles versus 662 predicted cycles (0% error): one
cold graph at 165 cycles and seven resident graphs at 71 cycles each. Physical
board acceptance reuses the trace but must replace these cycle constants with
calibrated controller and host-link measurements.

## Reproducible exit gate

`make phase10` runs all Python/DV tests, elaborates `rcif_fpga_top`, and simulates
the AXI reader's burst and backpressure behavior. A physical bitstream is not a
portable exit claim: it additionally requires a selected board overlay,
licensed vendor tools and memory IP, post-route timing closure, and on-board
execution.
