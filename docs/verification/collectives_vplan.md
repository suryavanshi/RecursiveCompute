# Collectives Verification Plan

## Scope and configuration

The target covers two through eight nodes, credit depths one through four,
ring/tree AllReduce, routed AllToAll, CRC retry and bounded persistent faults.
Partition identity is checked in the executable security monitor and must be
carried on the production fabric header before tapeout.

## Stimulus and checking

- Exhaustive Python exploration checks every bounded credit occupancy and the
  complete serialized packet routing state machine.
- Verilator tests cover engine, credit link and four-node cluster behavior.
- Fault tests inject transient and persistent CRC errors at every route step.
- Scoreboards compare reductions and AllToAll transpose with independent
  algorithmic models.

## Assertions and coverage

- Credits stay in `[0, depth]`; packet ownership equals consumed credit.
- A packet cannot escape its partition or be delivered twice.
- Every legal state has progress under the documented finite-stall fairness
  assumption; retries end in success or an explicit error.
- Cross topology, operation, node count, depth, route step and fault outcome.

The bounded protocol proof and simulations are closed. Concurrent virtual
channels, PHY training/faults and an RTL partition tag remain production fabric
signoff items.
