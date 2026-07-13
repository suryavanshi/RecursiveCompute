"""Simple event model for agentic LLM inference ASIC planning.

The model is intentionally small and transparent. It estimates TTFT/TPOT and
KV traffic from a workload trace, allowing early architecture exploration before
cycle-accurate simulators or RTL are available.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from statistics import median
from typing import Any, Iterable


@dataclass(frozen=True)
class ModelConfig:
    layers: int
    hidden_size: int
    num_q_heads: int
    num_kv_heads: int
    head_dim: int
    kv_bytes_per_element: float
    weight_bytes_per_token: float
    decode_ops_per_token: float
    prefill_ops_per_token: float

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "ModelConfig":
        return cls(
            layers=int(data["layers"]),
            hidden_size=int(data["hidden_size"]),
            num_q_heads=int(data["num_q_heads"]),
            num_kv_heads=int(data["num_kv_heads"]),
            head_dim=int(data["head_dim"]),
            kv_bytes_per_element=float(data.get("kv_bytes_per_element", 1.0)),
            weight_bytes_per_token=float(data["weight_bytes_per_token"]),
            decode_ops_per_token=float(data["decode_ops_per_token"]),
            prefill_ops_per_token=float(data["prefill_ops_per_token"]),
        )

    @property
    def kv_bytes_per_token(self) -> float:
        # K and V for every layer, using KV heads rather than Q heads for GQA/MQA.
        return (
            2.0
            * self.layers
            * self.num_kv_heads
            * self.head_dim
            * self.kv_bytes_per_element
        )


@dataclass(frozen=True)
class HardwareConfig:
    local_dram_bandwidth_bytes_s: float
    remote_kv_bandwidth_bytes_s: float
    prefill_ops_s: float
    decode_ops_s: float
    collective_latency_s: float
    kv_local_hit_rate: float
    kv_remote_hit_rate: float

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "HardwareConfig":
        local_hit = float(data["kv_local_hit_rate"])
        remote_hit = float(data["kv_remote_hit_rate"])
        if local_hit + remote_hit > 1.0:
            raise ValueError("kv_local_hit_rate + kv_remote_hit_rate must be <= 1")
        local_dram_bandwidth = data.get(
            "local_dram_bandwidth_bytes_s",
            data.get("local_hbm_bandwidth_bytes_s"),
        )
        if local_dram_bandwidth is None:
            raise ValueError("hardware requires local_dram_bandwidth_bytes_s")
        return cls(
            local_dram_bandwidth_bytes_s=float(local_dram_bandwidth),
            remote_kv_bandwidth_bytes_s=float(data["remote_kv_bandwidth_bytes_s"]),
            prefill_ops_s=float(data["prefill_ops_s"]),
            decode_ops_s=float(data["decode_ops_s"]),
            collective_latency_s=float(data["collective_latency_s"]),
            kv_local_hit_rate=local_hit,
            kv_remote_hit_rate=remote_hit,
        )


@dataclass(frozen=True)
class Request:
    request_id: str
    prefix_tokens: int
    reused_prefix_tokens: int
    new_prefill_tokens: int
    output_tokens: int
    tenant_id: str = "default"
    locality_domain: str = "default"
    priority: int = 0

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Request":
        prefix_tokens = int(data["prefix_tokens"])
        reused_prefix_tokens = int(data["reused_prefix_tokens"])
        new_prefill_tokens = int(data["new_prefill_tokens"])
        if reused_prefix_tokens > prefix_tokens:
            raise ValueError(f"{data['request_id']}: reused_prefix_tokens exceeds prefix_tokens")
        if reused_prefix_tokens + new_prefill_tokens < prefix_tokens:
            # This is legal for summarized traces, but it is usually a modeling bug.
            pass
        return cls(
            request_id=str(data["request_id"]),
            prefix_tokens=prefix_tokens,
            reused_prefix_tokens=reused_prefix_tokens,
            new_prefill_tokens=new_prefill_tokens,
            output_tokens=int(data["output_tokens"]),
            tenant_id=str(data.get("tenant_id", "default")),
            locality_domain=str(data.get("locality_domain", "default")),
            priority=int(data.get("priority", 0)),
        )


@dataclass(frozen=True)
class RequestResult:
    request_id: str
    ttft_s: float
    tpot_s: float
    total_decode_s: float
    kv_bytes_read: float
    kv_bytes_written: float
    weight_bytes_read: float
    local_kv_bytes: float
    remote_kv_bytes: float
    cold_kv_bytes: float

    def as_dict(self) -> dict[str, Any]:
        return {
            "request_id": self.request_id,
            "ttft_s": self.ttft_s,
            "tpot_s": self.tpot_s,
            "total_decode_s": self.total_decode_s,
            "kv_bytes_read": self.kv_bytes_read,
            "kv_bytes_written": self.kv_bytes_written,
            "weight_bytes_read": self.weight_bytes_read,
            "local_kv_bytes": self.local_kv_bytes,
            "remote_kv_bytes": self.remote_kv_bytes,
            "cold_kv_bytes": self.cold_kv_bytes,
        }


def validate_trace_shape(trace: dict[str, Any]) -> None:
    """Minimal schema validation using only the standard library."""

    required_top = {"trace_name", "model", "hardware", "requests"}
    missing = sorted(required_top - set(trace))
    if missing:
        raise ValueError(f"trace missing required fields: {', '.join(missing)}")
    if not isinstance(trace["requests"], list) or not trace["requests"]:
        raise ValueError("trace requests must be a non-empty list")
    ModelConfig.from_dict(trace["model"])
    HardwareConfig.from_dict(trace["hardware"])
    for request in trace["requests"]:
        Request.from_dict(request)


def percentile(values: Iterable[float], pct: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * pct
    low = int(rank)
    high = min(low + 1, len(ordered) - 1)
    frac = rank - low
    return ordered[low] * (1.0 - frac) + ordered[high] * frac


def simulate_request(model: ModelConfig, hardware: HardwareConfig, request: Request) -> RequestResult:
    kv_write_bytes = request.new_prefill_tokens * model.kv_bytes_per_token
    prefill_compute_s = (
        request.new_prefill_tokens * model.prefill_ops_per_token / hardware.prefill_ops_s
    )
    prefill_mem_s = kv_write_bytes / hardware.local_dram_bandwidth_bytes_s
    prefill_s = max(prefill_compute_s, prefill_mem_s)

    total_kv_read = 0.0
    total_local_kv = 0.0
    total_remote_kv = 0.0
    total_cold_kv = 0.0
    total_weight_read = 0.0
    total_decode_s = 0.0

    cold_hit_rate = 1.0 - hardware.kv_local_hit_rate - hardware.kv_remote_hit_rate
    for token_index in range(request.output_tokens):
        context_tokens = request.prefix_tokens + token_index
        kv_bytes = context_tokens * model.kv_bytes_per_token
        local_kv = kv_bytes * hardware.kv_local_hit_rate
        remote_kv = kv_bytes * hardware.kv_remote_hit_rate
        cold_kv = kv_bytes * cold_hit_rate

        # Cold KV is modeled as remote traffic plus a 4x penalty for promotion.
        kv_time_s = (
            local_kv / hardware.local_dram_bandwidth_bytes_s
            + remote_kv / hardware.remote_kv_bandwidth_bytes_s
            + cold_kv * 4.0 / hardware.remote_kv_bandwidth_bytes_s
        )
        weight_time_s = model.weight_bytes_per_token / hardware.local_dram_bandwidth_bytes_s
        compute_time_s = model.decode_ops_per_token / hardware.decode_ops_s
        token_s = max(kv_time_s, weight_time_s, compute_time_s) + hardware.collective_latency_s

        total_kv_read += kv_bytes
        total_local_kv += local_kv
        total_remote_kv += remote_kv
        total_cold_kv += cold_kv
        total_weight_read += model.weight_bytes_per_token
        total_decode_s += token_s

    tpot_s = total_decode_s / request.output_tokens
    return RequestResult(
        request_id=request.request_id,
        ttft_s=prefill_s + tpot_s,
        tpot_s=tpot_s,
        total_decode_s=total_decode_s,
        kv_bytes_read=total_kv_read,
        kv_bytes_written=kv_write_bytes,
        weight_bytes_read=total_weight_read,
        local_kv_bytes=total_local_kv,
        remote_kv_bytes=total_remote_kv,
        cold_kv_bytes=total_cold_kv,
    )


def simulate_trace(trace: dict[str, Any]) -> dict[str, Any]:
    validate_trace_shape(trace)
    model = ModelConfig.from_dict(trace["model"])
    hardware = HardwareConfig.from_dict(trace["hardware"])
    requests = [Request.from_dict(item) for item in trace["requests"]]
    results = [simulate_request(model, hardware, request) for request in requests]

    ttft = [result.ttft_s for result in results]
    tpot = [result.tpot_s for result in results]
    output_tokens = sum(request.output_tokens for request in requests)
    total_time = sum(result.ttft_s + result.total_decode_s for result in results)

    return {
        "trace_name": trace["trace_name"],
        "model": {
            "kv_bytes_per_token": model.kv_bytes_per_token,
        },
        "summary": {
            "requests": len(results),
            "output_tokens": output_tokens,
            "ttft_p50_s": median(ttft),
            "ttft_p95_s": percentile(ttft, 0.95),
            "ttft_p99_s": percentile(ttft, 0.99),
            "tpot_p50_s": median(tpot),
            "tpot_p95_s": percentile(tpot, 0.95),
            "tpot_p99_s": percentile(tpot, 0.99),
            "accepted_tokens_per_s": output_tokens / total_time if total_time > 0 else 0.0,
            "kv_bytes_read": sum(result.kv_bytes_read for result in results),
            "kv_bytes_written": sum(result.kv_bytes_written for result in results),
            "weight_bytes_read": sum(result.weight_bytes_read for result in results),
            "local_kv_bytes": sum(result.local_kv_bytes for result in results),
            "remote_kv_bytes": sum(result.remote_kv_bytes for result in results),
            "cold_kv_bytes": sum(result.cold_kv_bytes for result in results),
        },
        "requests": [result.as_dict() for result in results],
    }


def load_trace(path: Path | str) -> dict[str, Any]:
    trace_path = Path(path)
    with trace_path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the RCIF event simulator.")
    parser.add_argument("trace", type=Path, help="Path to an agentic coding trace JSON file.")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON output.")
    args = parser.parse_args()

    result = simulate_trace(load_trace(args.trace))
    print(json.dumps(result, indent=2 if args.pretty else None, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
