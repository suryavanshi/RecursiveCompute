# Descriptor Format

This is the initial software descriptor contract used by the simulator and later by RTL.

## Design Rules

- Descriptors are little-endian.
- All descriptors include a `request_id`.
- Descriptor streams are append-only for a token step.
- Faults report the descriptor index that caused the fault.
- Firmware prepares descriptors; hardware executes without firmware in the per-token critical path.

## Initial Descriptor Types

| Type | Purpose |
| --- | --- |
| `NOP` | Complete a command without side effects. |
| `ECHO` | Return the payload as the completion result. |
| `GET_COUNTER` | Return a scheduler counter selected by payload byte 0. |
| `KV_MAP` | Install or update virtual-to-physical KV page metadata. |
| `KV_TRANSLATE` | Translate a virtual KV page and return physical tier metadata. |
| `DMA_COPY` | Validate and enqueue a DMA copy descriptor. |
| `KV_PREFETCH` | Hint that a range of KV pages should be promoted or fetched. |
| `ATTN_DECODE` | Run streaming decode attention over a paged KV range. |
| `TENSOR_MATMUL` | Run a quantized matrix operation. |
| `NORM_ACT` | Run normalization and activation. |
| `COLLECTIVE` | Run AllReduce, AllGather, ReduceScatter, broadcast, or AllToAll. |
| `COMPLETE` | Write a completion entry for the request or token step. |

## Common Fields

```text
u16 descriptor_type
u16 descriptor_version
u32 descriptor_bytes
u64 request_id
u32 graph_node_id
u32 dependency_mask
u64 flags
```

## Versioning

The initial version is `0`. RTL may reject unsupported versions. The simulator should remain able to read older versions and translate them when possible.

## Current Smoke Opcode Map

| Opcode | Name | Payload |
| --- | --- | --- |
| `0x0000` | `NOP` | ignored |
| `0x0001` | `ECHO` | returned as completion result |
| `0x0010` | `GET_COUNTER` | bits `[7:0]` select counter |
| `0x0020` | `KV_MAP` | KV page descriptor |
| `0x0021` | `KV_TRANSLATE` | bits `[15:0]` select virtual page |
| `0x0022` | `KV_GET_FAULT` | pop the oldest KV page-fault record |
| `0x0030` | `DMA_COPY` | DMA copy descriptor |
| `0x0031` | `DMA_INDEX_WRITE` | program one gather-list entry |
| `0x0032` | `DMA_GATHER` | copy pages selected by a gather list |
| `0x0033` | `DMA_ECC_INJECT` | invert stored parity for one page |
| `0x0040` | `ATTN_QK_DOT` | signed-int8 four-element Q·K debug tile |

`KV_MAP` writes the SRAM-resident reference page table and also warms the TLB.
`KV_TRANSLATE` checks the TLB first; a miss walks the reference page table,
refills the TLB on a hit, and reports status `4` when the page table has no
mapping.

Current KV fault record layout:

| Bits | Field |
| --- | --- |
| `[15:0]` | faulting virtual page |
| `[47:16]` | request id |
| `[63:48]` | fault cause/status |

`KV_GET_FAULT` returns status `10` when the queue is empty. The bounded queue
retains the newest records if software falls behind; counter selector `3`
reports how many older records were overwritten.

Current KV page descriptor layout:

| Bits | Field |
| --- | --- |
| `[15:0]` | virtual page |
| `[31:16]` | physical page |
| `[35:32]` | tier |
| `[39:36]` | format |
| `[63:40]` | reserved, must be zero |

Current DMA copy descriptor layout:

| Bits | Field |
| --- | --- |
| `[15:0]` | source page |
| `[31:16]` | destination page |
| `[47:32]` | length |
| `[63:48]` | reserved, must be zero |

The current RTL interprets `length` as a count of page-model words. A successful
copy returns an XOR checksum of the copied data in the completion result. The
prototype gather/scatter SRAM model has 256 pages and returns status `9` when
the source or destination range exceeds that model.

Validated, nonzero `DMA_COPY` descriptors are submitted to a four-entry
descriptor-fetch FIFO before execution. The fetch stage holds source,
destination, and length stable until gather/scatter accepts the descriptor.
The DMA engine permits one executing descriptor in the smoke scheduler and
emits exactly one completion after the gather response.

`DMA_INDEX_WRITE` uses bits `[7:0]` for the list slot and `[23:8]` for its
physical source page; upper bits are reserved. `DMA_GATHER` uses the normal DMA
descriptor layout, interpreting `source page` as the first gather-list slot.
Every list entry is validated before copying begins. Missing entries return
status `11` and the missing list slot, preventing partial writes.

Every valid page-model word stores even parity. DMA execution scans all source
pages before modifying a destination; a mismatch returns status `12` and the
corrupt physical page. `DMA_ECC_INJECT` uses bits `[15:0]` as the physical page
and is a deterministic verification hook rather than a production command.
