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
| `0x0030` | `DMA_COPY` | DMA copy descriptor |

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
