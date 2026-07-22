# RTL

SystemVerilog source is split by subsystem. The Phase 7 collective block in
`rtl/collectives/` provides a credit link, programmable topology table, ring and
tree AllReduce, routed AllToAll, bounded link retry/fault containment, and a
four-chip distributed reference cluster whose endpoints communicate only over
the credit-link packet interface.

Phase 9 simulation assertions live in `rtl/verification/`. They are excluded
from synthesis and currently enforce top-level command/completion conservation
and completion stability under backpressure.

The board-neutral Phase 10 integration shell is in `fpga/rtl/`. It instantiates
the existing scheduler datapath and adds the AXI read-master boundary used by a
vendor DDR or HBM controller.
