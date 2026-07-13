"""Generate a deterministic synthetic agentic coding trace."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def build_trace(requests: int, prefix_tokens: int, reuse_ratio: float) -> dict:
    reused_prefix_tokens = int(prefix_tokens * reuse_ratio)
    new_prefill_tokens = prefix_tokens - reused_prefix_tokens
    return {
        "trace_name": "generated_agentic_coding_trace",
        "description": "Generated deterministic trace for architecture experiments.",
        "model": {
            "layers": 96,
            "hidden_size": 32768,
            "num_q_heads": 128,
            "num_kv_heads": 8,
            "head_dim": 256,
            "kv_bytes_per_element": 1,
            "weight_bytes_per_token": 500000000000,
            "decode_ops_per_token": 1000000000000,
            "prefill_ops_per_token": 1000000000000,
        },
        "hardware": {
            "local_dram_bandwidth_bytes_s": 800000000000,
            "remote_kv_bandwidth_bytes_s": 224000000000,
            "prefill_ops_s": 5000000000000000,
            "decode_ops_s": 1000000000000000,
            "collective_latency_s": 0.001,
            "kv_local_hit_rate": 0.9,
            "kv_remote_hit_rate": 0.08,
        },
        "requests": [
            {
                "request_id": f"generated-{index:04d}",
                "tenant_id": "tenant-a",
                "locality_domain": "rack-0-domain-0",
                "priority": 10,
                "prefix_tokens": prefix_tokens,
                "reused_prefix_tokens": reused_prefix_tokens,
                "new_prefill_tokens": new_prefill_tokens,
                "output_tokens": 512 + (index % 4) * 256,
            }
            for index in range(requests)
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate an RCIF agentic coding trace.")
    parser.add_argument("--requests", type=int, default=4)
    parser.add_argument("--prefix-tokens", type=int, default=131072)
    parser.add_argument("--reuse-ratio", type=float, default=0.9)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    trace = build_trace(args.requests, args.prefix_tokens, args.reuse_ratio)
    args.output.write_text(json.dumps(trace, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
