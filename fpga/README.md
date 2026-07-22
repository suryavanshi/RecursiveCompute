# Phase 10 FPGA/Emulation Prototype

This directory contains the reduced RCIF D-chip prototype boundary. It maps the
Phase 6 token scheduler, attention engine, tensor array, DMA, graph SRAM, and
completion path into `rcif_fpga_top`. `rcif_ddr_axi_reader` is a synthesizable
AXI4 read master intended to connect to vendor DDR/HBM controller IP; no vendor
pinout or memory-controller model is silently assumed.

`vivado/build.tcl` synthesizes the board-neutral design for a VCU118-class
default part. Set `RCIF_FPGA_PART` and add a board overlay XDC for another
device. The script produces a post-synthesis checkpoint plus utilization and
timing reports, but deliberately does not claim placement, routing, or a
bitstream without a selected board and licensed vendor tools.

The deterministic backend in `fpga/prototype.py` is the pre-board emulator. It
uses the Phase 8 secure-boot and host-driver path, accepts the exact frozen
128-bit graph nodes, accounts external-memory cycles, migrates host-resident KV
pages into the local-DDR proxy after faults, and executes quantized attention
and GEMV against the independent golden references.

Run the complete reproducible gate with:

```bash
make phase10
```

Use `make local-phase10` when Verilator is installed locally. Physical board
closure additionally requires a board overlay, vendor DDR/HBM IP, PCIe or SoC
host bridge, post-route timing closure, and an on-board run of the same trace.
