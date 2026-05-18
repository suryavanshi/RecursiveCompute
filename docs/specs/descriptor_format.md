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
| `KV_MAP` | Install or update virtual-to-physical KV page metadata. |
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

