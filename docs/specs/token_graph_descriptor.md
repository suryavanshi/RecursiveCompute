# Token Graph Descriptor

Phase 6 uses a fixed 128-bit little-endian node descriptor. Firmware writes a
graph into the scheduler descriptor SRAM, then submits a request containing a
base index, node count, request id, and two-bit priority. A graph contains at
most eight nodes in the bounded prototype.

## Node Layout

| Bits | Field | Meaning |
| --- | --- | --- |
| `[3:0]` | opcode | Node operation. |
| `[7:4]` | flags | Opcode-specific flags. Unused bits must be zero. |
| `[11:8]` | node id | Scoreboard bit written when the node completes. |
| `[19:12]` | dependency mask | Required completed node-id bits. |
| `[83:20]` | operand 0 | Primary operation payload. |
| `[115:84]` | operand 1 | Secondary operation payload. |
| `[127:116]` | reserved | Must be zero. |

Node ids need not match descriptor SRAM order. The scheduler scans the graph
from its base after every completion, skips completed or blocked nodes, and
issues the first ready node. A full scan with no ready node reports
`GRAPH_DEADLOCK` rather than hanging.

## Opcodes

| Opcode | Name | Operands |
| --- | --- | --- |
| `0x0` | `NOP` | Operand 0 is XORed into the graph result. |
| `0x1` | `DMA` | Operand 0 is the existing 64-bit DMA descriptor. Flag 0 selects gather instead of copy. |
| `0x2` | `ATTENTION` | Operand 0 holds request configuration; operand 1 is the explicit 32-token mask. |
| `0x3` | `TENSOR` | Operand 0 holds four INT8 activations; operand 1 holds post-processing controls. Flag 3 consumes the previous engine result instead. |
| `0xf` | `COMPLETE` | Finishes the request after its dependencies; completion result is the graph XOR result XOR operand 0. |

The attention request in operand 0 is:

| Bits | Field |
| --- | --- |
| `[2:0]` | query head |
| `[6:3]` | number of query heads |
| `[9:7]` | number of KV heads |
| `[15:10]` | context tokens |
| `[21:16]` | sliding-window start |
| `[27:22]` | attention-sink tokens |
| `[28]` | explicit-mask enable |

The tensor controls in operand 1 are activation mode in `[1:0]`, normalization
enable in bit 2, and normalization epsilon in `[18:3]`. Weight rows and
attention query/page/KV memories are programmed through their engine-facing
ports before graph submission, modeling DMA delivery into local SRAM.

## Scheduling and QoS

The request queue has four entries. The scheduler runs one graph at a time and
chooses the highest priority pending graph at each graph boundary. Equal
priorities retain submission order. Running graphs are not preempted, so a
priority-3 request cannot be bypassed by queued lower-priority work. With four
request slots and the default 6,400-cycle graph-service allocation, an accepted
priority-3 request has a 32,000-cycle admission-to-internal-retirement bound.
This includes an active graph, every possible older equal-priority request, and
the request's own execution. Host completion backpressure is excluded from the
scheduler bound and absorbed by the completion FIFO. The derivation and runtime
monitors are specified in `docs/verification/scheduler_vplan.md`.

## Replay Trace

The bounded 64-entry replay RAM records separate issue and finish events. Each
event contains request id, opcode, node id, phase, status, and a truncated
result payload. Cycle numbers are deliberately excluded, making the event
stream stable under completion backpressure. Trace overflow is sticky until
the trace is cleared.

## Status Codes

| Value | Name | Meaning |
| --- | --- | --- |
| `13` | `GRAPH_INVALID` | Invalid opcode, flags, node id, reserved bits, or descriptor. |
| `14` | `GRAPH_DEADLOCK` | No incomplete node has all dependencies satisfied. |
| `15` | `TENSOR_CONFIG` | The tensor engine rejected its programmed format or request controls. |

The prototype executes one engine node at a time. This intentionally favors
deterministic behavior and verification clarity; overlapping independent graph
nodes is a later throughput optimization that does not change the descriptor
contract.
