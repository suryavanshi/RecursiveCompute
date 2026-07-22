# RCIF Collective Protocol

Phase 7 defines the bounded model-parallel fabric used by the first RTL
prototype. The reference configuration has four nodes; node and payload widths
remain elaboration parameters.

## Command and Completion Contract

A collective command contains an opcode, collective id, partition id,
participant mask, root, retry limit, and payload. Ring and tree AllReduce read
one `DATA_W` partial from each participating node. AllToAll reads a
source-major matrix, `input[source][destination]`. A successful AllToAll
completion is destination-major, `output[destination][source]`.

Completions are atomic. `committed=1` only accompanies `OK`; every failure
returns zero payloads so a consumer cannot observe a partially reduced tensor
or partially delivered expert batch. Completion fields remain stable until the
consumer accepts them.

| Opcode | Value | Operation |
| --- | ---: | --- |
| `RING_ALLREDUCE` | 0 | Modular unsigned sum around the programmed ring, followed by a ring broadcast. |
| `TREE_ALLREDUCE` | 1 | Leaf-to-root modular unsigned sum, followed by parent-to-child broadcast. |
| `ALLTOALL` | 2 | Route every source/destination payload using the topology next-hop table. |

Addition wraps at `DATA_W`. Signed/floating reduction is a future datapath
extension; routing and failure semantics remain unchanged.

## Packet Header

`rcif_collective_header_t` is a fixed 64-bit header defined in
`rtl/collectives/rcif_collective_protocol_pkg.sv`.

| Field | Bits | Meaning |
| --- | ---: | --- |
| version | 4 | Protocol version; Phase 7 is 1. |
| opcode | 3 | Collective operation. |
| phase | 3 | Data, reduce, broadcast, acknowledgement, or retry. |
| partition id | 8 | Isolation domain checked at every hop. |
| collective id | 8 | Matches packets and completion. |
| source/destination | 4 each | Logical endpoints. |
| chunk/sequence | 4 each | Ordering within a collective. |
| hop limit | 7 | Bounds malformed or cyclic routes. |
| retry | 7 | Attempt number for the current hop. |
| header CRC | 8 | CRC-8 over the header with this field cleared. |

Payload data follows the header. A production link adapter may segment a
payload into PHY-width flits without changing the logical header.

## Credit Flow and Deadlock Rule

Each directed link uses `rcif_credit_link`, a ready/valid FIFO whose advertised
credit count is exactly `depth - occupancy`. A transmitter may only send when
credit is nonzero. A receiver consumes a complete flit locally before it
requests any downstream credit: RCIF never holds one channel while waiting for
another. This consume-then-forward rule removes circular wait from the bounded
ring and routed topologies.

RTL assertions prove occupancy bounds and response stability. The exhaustive
state checks in `dv/tests/collectives/test_credit_protocol.py` enumerate every
link-occupancy state and the complete serialized packet transition system for
ring AllReduce, tree reduce/broadcast, and ring-routed AllToAll, for two through
eight nodes and credit depths one through four. Packet ownership, route step,
link occupancy, advertised credits, bounded-fair receiver stalls, transient
retry, and persistent retry exhaustion are included in the state. More than one
million protocol states are visited. Under the legal liveness assumption that
a receiver is eventually ready, every nonterminal state has a progress
transition and every path reaches either atomic completion or a reported retry
failure; a full ring cannot form a channel-dependency cycle.

## Topology Table

Each node entry contains:

- active bit and partition id;
- ring successor;
- tree parent (the root is its own parent);
- per-destination next hop;
- enable state for every directed physical link.

Programming is only permitted while software has quiesced collective traffic.
The reference RTL exposes configuration ports for verification; Phase 8 maps
the same fields into the firmware register interface.

Before accepting payload movement, the engine requires a nonempty participant
mask, an active participating root, active participants, and matching
partitions. Each hop rechecks endpoint activity, membership, partition, link
enable, and hop limit. A ring that closes before visiting every participant, a
tree cycle/disconnection, a disabled link, or a self-routing next hop reports a
topology error rather than hanging.

## Retry and Fault Containment

Fault injection identifies one directed edge and selects transient or
persistent behavior. A transient failure consumes one retry and then clears.
A persistent failure retries the same packet until `retry_limit` is exhausted.
Retries never advance sequence, reduction state, route position, or output
visibility.

| Status | Value | Meaning |
| --- | ---: | --- |
| `OK` | 0 | Operation committed. |
| `BAD_COMMAND` | 1 | Invalid opcode, participant mask, or root. |
| `TOPOLOGY` | 2 | Disconnected, cyclic, disabled, or self-routed edge. |
| `PARTITION` | 3 | Packet would enter or leave its configured partition. |
| `RETRY_EXHAUSTED` | 4 | Persistent link fault exceeded the retry budget. |
| `HOP_LIMIT` | 5 | AllToAll route did not reach its destination in time. |

All failures name the relevant source/destination edge when available and
commit no data. Fault state is contained within the collective engine; later
commands can proceed after software clears or reprograms the failing link.

## Distributed Reference Cluster

`rcif_collective_cluster.sv` instantiates four independent
`rcif_ring_collective_node.sv` endpoints. No endpoint reads another endpoint's
local value or state. The only data path between nodes is a directed
`rcif_credit_link` FIFO carrying the versioned packet header and reduction
payload. The root injects a reduce packet, each node consumes and forwards it,
and the root injects a separate broadcast packet after the reduction returns.

The Verilator cluster test supplies independent receiver backpressure with a
bounded-fair schedule, checks every physical credit count every cycle, completes
two back-to-back sharded reductions, and verifies that all four chips receive
the same result. Cluster completion requires every endpoint idle and every link
fully credited, so a result cannot retire while an orphan packet remains.

## Integration Boundary

The engine is a direct collective-queue target and can run independently of a
token graph. A scheduler graph node will carry a collective-queue descriptor,
not inline all node payloads. Phase 8 firmware owns queue allocation and
topology programming; the Phase 7 interface freezes the hardware behavior it
will target.
