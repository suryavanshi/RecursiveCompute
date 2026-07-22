"""End-to-end Phase 10 FPGA prototype backend.

This is not a claim of physical-board execution.  It is the deterministic,
cycle-accounted backend used before a vendor DDR controller and PCIe endpoint
are available.  It consumes the frozen Phase 6 descriptors through the Phase 8
host driver and mirrors the reduced FPGA shell in ``fpga/rtl``.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable

from dv.golden.attention_ref import rtl_online_attention
from dv.golden.tensor_ref import quantized_gemv
from runtime.driver.device import MASK64, RcifDevice
from runtime.driver.protocol import (
    Command,
    Completion,
    Counter,
    GraphNode,
    GraphOpcode,
    Status,
)

from .memory import ExternalMemory, MemoryTiming


GRAPH_FLAG_TENSOR_USE_PREVIOUS = 0x8


@dataclass(frozen=True)
class ToyModel:
    query: tuple[int, int, int, int]
    keys: tuple[tuple[int, int, int, int], ...]
    values: tuple[tuple[int, int, int, int], ...]
    packed_rows: tuple[int, int, int, int]
    scales_q8_8: tuple[int, int, int, int] = (256, 256, 256, 256)
    biases: tuple[int, int, int, int] = (0, 0, 0, 0)


DEFAULT_TOY_MODEL = ToyModel(
    query=(2, -1, 3, 1),
    keys=((1, 0, 1, 0), (2, -1, 2, 1), (-1, 1, 0, 2), (3, 0, 2, -1)),
    values=((4, 1, -2, 3), (6, 2, 0, 4), (-2, 5, 1, 0), (8, -1, 3, 2)),
    packed_rows=(0x01010101, 0x01FF0100, 0x000101FF, 0xFF010001),
)


@dataclass(frozen=True)
class ExecutionRecord:
    request_id: int
    cycles: int
    predicted_cycles: int
    output: tuple[int, ...]
    page_faults: int
    migrations: int


@dataclass(frozen=True)
class Phase10Report:
    graphs: int
    measured_cycles: int
    predicted_cycles: int
    tolerance: float
    page_faults: int
    migrations: int
    bytes_migrated: int

    @property
    def relative_error(self) -> float:
        if self.predicted_cycles == 0:
            return 0.0
        return abs(self.measured_cycles - self.predicted_cycles) / self.predicted_cycles


def build_toy_graph(kv_virtual_page: int = 1) -> tuple[GraphNode, ...]:
    """Return the real four-node descriptor graph used by the prototype."""
    attention_config = 1 | (1 << 3) | (1 << 7) | (4 << 10)
    return (
        GraphNode(GraphOpcode.DMA, 0, operand0=kv_virtual_page),
        GraphNode(GraphOpcode.ATTENTION, 1, dependencies=1, operand0=attention_config),
        GraphNode(
            GraphOpcode.TENSOR,
            2,
            dependencies=2,
            flags=GRAPH_FLAG_TENSOR_USE_PREVIOUS,
        ),
        GraphNode(GraphOpcode.COMPLETE, 3, dependencies=4),
    )


class FpgaPrototypeDevice(RcifDevice):
    """Phase 8-compatible device that executes the reduced FPGA datapath."""

    DMA_BASE_CYCLES = 6
    ATTENTION_BASE_CYCLES = 9
    ATTENTION_TOKEN_CYCLES = 3
    TENSOR_CYCLES = 12
    NODE_SCHEDULER_CYCLES = 2

    def __init__(
        self,
        *,
        local_pages: int = 32,
        timing: MemoryTiming | None = None,
        model: ToyModel = DEFAULT_TOY_MODEL,
    ):
        super().__init__()
        self.memory = ExternalMemory(local_pages, timing)
        self.model = model
        self.records: dict[int, ExecutionRecord] = {}
        self.outputs: dict[int, tuple[int, ...]] = {}
        self.memory.map_page(1, (model.keys, model.values), 32, tier="host")

    def _execute_graph(self, command: Command) -> None:
        graph = command.graph
        if not graph or len(graph) > 8 or not 0 <= command.priority <= 3:
            self._complete(Completion(command.request_id, Status.GRAPH_INVALID))
            return
        self._increment_graph_nodes(len(graph))
        complete_mask = 0
        remaining = list(graph)
        result = 0
        cycles = 0
        predicted = 0
        output: tuple[int, ...] = ()
        attention: list[int] | None = None
        start_faults = self.memory.page_faults
        start_migrations = self.memory.migrations

        while remaining:
            progressed = False
            for node in tuple(remaining):
                if node.node_id > 7 or node.dependencies & ~complete_mask:
                    continue
                cycles += self.NODE_SCHEDULER_CYCLES
                predicted += self.NODE_SCHEDULER_CYCLES
                try:
                    if node.opcode == GraphOpcode.NOP:
                        result ^= node.operand0
                    elif node.opcode == GraphOpcode.DMA:
                        was_local = self.memory.pages[node.operand0].tier == "local"
                        size_bytes = self.memory.pages[node.operand0].size_bytes
                        page, memory_cycles, migrated = self.memory.ensure_local(node.operand0)
                        del page
                        if migrated:
                            self._increment(Counter.KV_FAULTS)
                            self._increment(Counter.KV_RECOVERED)
                        op_cycles = self.DMA_BASE_CYCLES + memory_cycles
                        cycles += op_cycles
                        predicted += self.DMA_BASE_CYCLES + (
                            self.memory.timing.local_read_cycles
                            if was_local
                            else self.memory.timing.migration_cycles(size_bytes)
                        )
                    elif node.opcode == GraphOpcode.ATTENTION:
                        was_local = self.memory.pages[1].tier == "local"
                        size_bytes = self.memory.pages[1].size_bytes
                        page, memory_cycles, migrated = self.memory.ensure_local(1)
                        if migrated:
                            self._increment(Counter.KV_FAULTS)
                            self._increment(Counter.KV_RECOVERED)
                        keys, values = page.payload
                        attention = rtl_online_attention(
                            list(self.model.query),
                            [list(item) for item in keys],
                            [list(item) for item in values],
                        )
                        op_cycles = (
                            self.ATTENTION_BASE_CYCLES
                            + len(keys) * self.ATTENTION_TOKEN_CYCLES
                            + memory_cycles
                        )
                        cycles += op_cycles
                        predicted += (
                            self.ATTENTION_BASE_CYCLES
                            + len(keys) * self.ATTENTION_TOKEN_CYCLES
                            + (
                                self.memory.timing.local_read_cycles
                                if was_local
                                else self.memory.timing.migration_cycles(size_bytes)
                            )
                        )
                        result ^= _pack_int16(attention)
                    elif node.opcode == GraphOpcode.TENSOR:
                        if node.flags != GRAPH_FLAG_TENSOR_USE_PREVIOUS or attention is None:
                            raise ValueError("tensor node requires previous attention result")
                        values, _ = quantized_gemv(
                            [max(-128, min(127, item)) for item in attention],
                            list(self.model.packed_rows),
                            ["int8"] * 4,
                            [0] * 4,
                            list(self.model.scales_q8_8),
                            list(self.model.biases),
                        )
                        output = tuple(values)
                        cycles += self.TENSOR_CYCLES
                        predicted += self.TENSOR_CYCLES
                        result ^= _pack_int16(values)
                    elif node.opcode == GraphOpcode.COMPLETE:
                        completion = Completion(command.request_id, Status.OK, result & MASK64)
                        self.outputs[command.request_id] = output
                        self.records[command.request_id] = ExecutionRecord(
                            command.request_id,
                            cycles,
                            predicted,
                            output,
                            self.memory.page_faults - start_faults,
                            self.memory.migrations - start_migrations,
                        )
                        self._complete(completion)
                        return
                    else:
                        raise ValueError("unsupported graph opcode")
                except (KeyError, ValueError):
                    self._complete(
                        Completion(command.request_id, Status.GRAPH_INVALID, node.opcode)
                    )
                    return
                complete_mask |= 1 << node.node_id
                remaining.remove(node)
                progressed = True
                break
            if not progressed:
                self._complete(
                    Completion(command.request_id, Status.GRAPH_DEADLOCK, complete_mask)
                )
                return
        self._complete(Completion(command.request_id, Status.GRAPH_INVALID, complete_mask))

    def migrate_to_host(self, virtual_page: int) -> None:
        page = self.memory.pages[virtual_page]
        page.tier = "host"
        page.physical_page = -1

    def _increment_graph_nodes(self, amount: int) -> None:
        self._increment(Counter.GRAPH_NODES, amount)


def run_agentic_trace(driver: Any, device: FpgaPrototypeDevice, trace: dict[str, Any]) -> Phase10Report:
    """Submit one real token graph per synthetic output token."""
    graphs = 0
    measured = 0
    predicted = 0
    tolerance = float(trace.get("cycle_tolerance", 0.05))
    for request in trace["requests"]:
        priority = min(3, max(0, int(request.get("priority", 0))))
        for _ in range(int(request["output_tokens"])):
            request_id = driver.submit_graph(build_toy_graph(), priority=priority)
            completion = driver.wait(request_id)
            if completion.status != Status.OK:
                raise RuntimeError("prototype graph failed with {}".format(completion.status))
            record = device.records[request_id]
            graphs += 1
            measured += record.cycles
            predicted += record.predicted_cycles
    return Phase10Report(
        graphs,
        measured,
        predicted,
        tolerance,
        device.memory.page_faults,
        device.memory.migrations,
        device.memory.bytes_migrated,
    )


def _pack_int16(values: Iterable[int]) -> int:
    packed = 0
    for index, value in enumerate(values):
        packed |= (value & 0xFFFF) << (index * 16)
    return packed
