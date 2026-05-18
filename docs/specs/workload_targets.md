# Workload Targets

This document defines the initial target workloads for the Recursive Compute Inference Fabric prototype. These are simulation targets for early architecture work, not silicon commitments.

## Primary Workload

The first workload is an agentic coding loop:

- A large stable prefix containing system instructions, developer policy, repository map, retrieved files, and prior tool outputs.
- Many follow-up decode turns that reuse most of the prefix.
- Output lengths from short tool calls to multi-file patch generation.
- Strict p95 and p99 latency requirements, because high jitter makes agents feel stalled.

## Sequence Classes

| Class | Prefix tokens | New prefill tokens | Output tokens | Expected reuse |
| --- | ---: | ---: | ---: | ---: |
| Small repo edit | 32K | 512-4K | 128-1K | 70-95% |
| Large repo edit | 128K | 1K-16K | 512-4K | 80-98% |
| Deep context coding | 1M | 4K-64K | 1K-8K | 90-99% |

## Model Classes

| Class | Parameter shape | Attention | Target use |
| --- | --- | --- | --- |
| Dense-500B | dense 500B | GQA/MQA preferred | baseline large coding model |
| Dense-1T | dense 1T | GQA/MQA preferred | upper dense baseline |
| MoE-1T-5T | sparse active experts | GQA/MQA preferred | scalable agentic model |

## First Targets

| Metric | First target | Stretch target |
| --- | ---: | ---: |
| TTFT p95 after prefix hit | <= 250 ms | <= 100 ms |
| TPOT p95 | <= 15 ms/token | <= 5 ms/token |
| KV prefix hit rate | >= 80% | >= 95% |
| HBM bytes per output token | measured and falling | workload-specific minimum |
| Collective share of TPOT | <= 20% | <= 10% |

## Measurements

Every simulator and RTL run should report:

- TTFT p50/p95/p99.
- TPOT p50/p95/p99.
- Output tokens per second under SLA.
- KV bytes read, written, promoted, and evicted.
- KV page hit rate by tier.
- HBM bytes per generated token.
- Collective time per token.
- Estimated energy per token once power models exist.

## Trace Requirements

Every workload trace must include:

- Model configuration.
- Hardware configuration.
- Request list.
- Prefix reuse amount per request.
- New prefill tokens per request.
- Output tokens per request.
- Expected locality domain.
- Optional priority and tenant fields.

