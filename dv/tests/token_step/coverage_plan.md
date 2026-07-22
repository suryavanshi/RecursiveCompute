# Token-Step Scheduler Coverage Plan

The directed Verilator test covers the Phase 6 bounded scheduler contract:

- a transformer block spanning DMA, paged attention, tensor, and completion;
- descriptors stored out of dependency order;
- a two-layer toy graph;
- attention output consumed by the tensor node through `USE_PREVIOUS`;
- bit-identical graph result and replay trace across repeated execution;
- graph-boundary priority ordering with FIFO age tie-breaking;
- a 32,000-cycle maximum-priority admission-to-retirement bound, exercised
  behind a seven-node maximum-length DMA graph and a queued low-priority graph;
- the same bound at full queue occupancy with one active plus four
  maximum-service priority-3 graphs, including equal-priority age ordering;
- sticky graph-service and maximum-priority latency violation monitors;
- self-dependency detection and `GRAPH_DEADLOCK` completion;
- issue and finish trace records for every successful node.

Remaining production work includes concurrent independent-node issue,
preemption, descriptor fetch from system memory,
trace streaming, graph snapshot/isolation across tenants, and formal proofs for
scoreboard safety and starvation bounds.
