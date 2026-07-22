# Collective Engine Coverage Plan

The Phase 7 bounded target is four nodes, with parameterized RTL supporting up
to the topology size selected at elaboration.

## Covered

- Ring AllReduce reduction and broadcast phases over four participating nodes.
- Tree reduction and broadcast with a programmed root/parent table.
- MoE AllToAll source/destination transpose through programmed next-hop routes.
- Credit counters exhaustively checked for depths one through four and ring
  sizes two through eight; a receiver never depends on downstream credit.
- RTL credit FIFO fill, full backpressure, ordered drain, stalled-payload
  stability, credit return, and flush recovery.
- Four independently instantiated collective nodes connected exclusively by
  four RTL credit links; two back-to-back sharded reductions complete under
  independently injected bounded-fair receiver stalls.
- Complete serialized packet transition system for ring, tree, and routed
  AllToAll across two through eight nodes, including packet ownership, route
  position, credits, backpressure, transient retry, and persistent exhaustion.
- Transient link failure succeeds after exactly one retry.
- Persistent link failure exhausts the configured retry budget, reports the
  failing edge, and commits no partial result.
- Partition mismatch is rejected before packet movement.
- Stable responses under completion backpressure are asserted in RTL.

## Remaining scale coverage

- Gate-level SerDes CRC corruption and analog link-training faults.
- Random topologies beyond eight nodes and multiple concurrent virtual channels.
- Performance saturation with multiple independent collective engines.

Those items require the Phase 9 UVM/fabric environment; they do not change the
Phase 7 packet, topology, or completion contract.
