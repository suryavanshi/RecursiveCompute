"""Small executable monitors for the Phase 9 full-chip safety contract.

These models are intentionally independent of the RTL implementation.  They
provide deterministic negative tests for invariants that the current bounded
top-level interface cannot yet encode directly (notably tenant and partition
identity) and a scoreboard for trace-driven full-chip tests.
"""

from __future__ import annotations

import itertools
from collections import Counter, deque
from dataclasses import dataclass, field
from typing import Any, Iterable


class VerificationError(AssertionError):
    """A Phase 9 safety or liveness contract was violated."""


@dataclass
class FullChipMonitor:
    dma_windows: dict[str, tuple[int, int]]
    node_partitions: dict[int, str]
    accepted: Counter[str] = field(default_factory=Counter)
    completed: Counter[str] = field(default_factory=Counter)
    kv_pages: dict[tuple[str, int], int] = field(default_factory=dict)
    refcounts: Counter[tuple[str, int]] = field(default_factory=Counter)
    ready_dependencies: set[str] = field(default_factory=set)

    def accept(self, request_id: str) -> None:
        self.accepted[request_id] += 1

    def complete(self, request_id: str) -> None:
        if self.completed[request_id] >= self.accepted[request_id]:
            raise VerificationError("completion without exactly one accepted command")
        self.completed[request_id] += 1

    def assert_drained(self) -> None:
        if self.accepted != self.completed:
            raise VerificationError("accepted command did not receive exactly one completion")

    def map_kv(self, tenant: str, virtual_page: int, physical_page: int) -> None:
        key = (tenant, virtual_page)
        self.kv_pages[key] = physical_page
        self.refcounts[key] += 1

    def read_kv(self, requester: str, owner: str, virtual_page: int) -> int:
        if requester != owner:
            raise VerificationError("cross-tenant KV access")
        key = (owner, virtual_page)
        if key not in self.kv_pages:
            raise KeyError(key)
        return self.kv_pages[key]

    def release_kv(self, tenant: str, virtual_page: int) -> None:
        key = (tenant, virtual_page)
        if self.refcounts[key] == 0:
            raise VerificationError("KV refcount underflow")
        self.refcounts[key] -= 1

    def dma(self, tenant: str, address: int, length: int) -> None:
        if length <= 0:
            raise VerificationError("DMA length must be positive")
        if tenant not in self.dma_windows:
            raise VerificationError("tenant has no DMA aperture")
        lower, upper = self.dma_windows[tenant]
        end = address + length
        if end < address or address < lower or end > upper:
            raise VerificationError("DMA outside permitted physical range")

    def dependency_ready(self, dependency: str) -> None:
        self.ready_dependencies.add(dependency)

    def issue(self, dependencies: Iterable[str]) -> None:
        missing = set(dependencies) - self.ready_dependencies
        if missing:
            raise VerificationError(f"scheduler issue before dependency ready: {sorted(missing)}")

    def route_collective(self, source: int, destination: int) -> None:
        if self.node_partitions.get(source) != self.node_partitions.get(destination):
            raise VerificationError("collective packet escaped its partition")


class CrossCoverage:
    PAGE_SIZES = (16, 32, 64, 128)
    PRECISIONS = ("int4", "fp4", "fp8", "bf16")
    MASKS = ("causal", "sliding", "sink", "sparse")
    PRIORITIES = (0, 1, 2, 3)
    FAULTS = ("none", "kv_miss", "dma_range", "ecc", "retry")

    def __init__(self) -> None:
        self.hits: Counter[tuple[Any, ...]] = Counter()

    @classmethod
    def required_bins(cls) -> set[tuple[Any, ...]]:
        return set(itertools.product(
            cls.PAGE_SIZES, cls.PRECISIONS, cls.MASKS,
            cls.PRIORITIES, cls.FAULTS,
        ))

    def sample(self, page_size: int, precision: str, mask: str,
               priority: int, fault: str) -> None:
        point = (page_size, precision, mask, priority, fault)
        if point not in self.required_bins():
            raise VerificationError(f"illegal cross-coverage point: {point}")
        self.hits[point] += 1

    def close(self) -> None:
        missing = self.required_bins() - set(self.hits)
        if missing:
            raise VerificationError(f"{len(missing)} cross-coverage bins unhit")


def run_trace(trace: dict[str, Any]) -> tuple[FullChipMonitor, CrossCoverage]:
    monitor = FullChipMonitor(
        dma_windows={name: tuple(window) for name, window in trace["dma_windows"].items()},
        node_partitions={int(node): partition
                         for node, partition in trace["node_partitions"].items()},
    )
    coverage = CrossCoverage()
    for operation in trace["operations"]:
        kind = operation["kind"]
        request_id = operation["request_id"]
        monitor.accept(request_id)
        if kind == "kv":
            monitor.map_kv(operation["tenant"], operation["virtual_page"],
                           operation["physical_page"])
            monitor.read_kv(operation["tenant"], operation["tenant"],
                            operation["virtual_page"])
        elif kind == "dma":
            monitor.dma(operation["tenant"], operation["address"], operation["length"])
        elif kind == "scheduler":
            for dependency in operation["dependencies"]:
                monitor.dependency_ready(dependency)
            monitor.issue(operation["dependencies"])
        elif kind == "collective":
            monitor.route_collective(operation["source"], operation["destination"])
        else:
            raise VerificationError(f"unsupported trace operation: {kind}")
        monitor.complete(request_id)
        coverage.sample(operation["page_size"], operation["precision"],
                        operation["mask"], operation["priority"], operation["fault"])
    monitor.assert_drained()
    return monitor, coverage


def exhaust_legal_backpressure(depth: int = 4, steps: int = 12) -> int:
    """Explore a bounded valid/ready queue and prove every state can drain."""
    initial = (0, 0, 0)
    pending = deque([initial])
    visited = {initial}
    while pending:
        occupancy, stall_age, elapsed = pending.popleft()
        if not 0 <= occupancy <= depth:
            raise VerificationError("queue occupancy escaped bounds")
        if elapsed == steps:
            continue
        for enqueue, dequeue in itertools.product((False, True), repeat=2):
            if enqueue and occupancy == depth:
                continue
            if dequeue and occupancy == 0:
                continue
            next_occupancy = occupancy + int(enqueue) - int(dequeue)
            next_stall = 0 if dequeue else (stall_age + 1 if occupancy else 0)
            if next_stall > depth:
                continue
            state = (next_occupancy, next_stall, elapsed + 1)
            if state not in visited:
                visited.add(state)
                pending.append(state)
    return len(visited)
