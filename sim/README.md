# Simulation

Architecture simulators and synthetic workload generators live here. The first simulator is a standard-library event model for KV/cache sensitivity studies.

`workloads/phase10_fpga_trace.json` is the compact acceptance trace consumed by
the external-memory FPGA emulation backend. It submits eight real token graphs
through the host driver and gates measured versus predicted cycles at 5%.
