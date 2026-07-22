"""Deterministic control-plane device model used by firmware and driver DV."""

from collections import deque
from typing import Deque, Dict, Generic, Iterable, Optional, Tuple, TypeVar

from .protocol import (
    Command,
    CommandOpcode,
    Completion,
    Counter,
    DeviceStatus,
    Fault,
    GraphOpcode,
    Status,
)

T = TypeVar("T")
MASK64 = (1 << 64) - 1


class Ring(Generic[T]):
    def __init__(self, entries: int):
        if entries < 4 or entries > 1024 or entries & (entries - 1):
            raise ValueError("ring size must be a power of two from 4 through 1024")
        self.entries = entries
        self._items: Deque[T] = deque()
        self.head = 0
        self.tail = 0

    def push(self, item: T) -> bool:
        if len(self._items) == self.entries:
            return False
        self._items.append(item)
        self.tail = (self.tail + 1) & 0xFFFFFFFF
        return True

    def pop(self) -> Optional[T]:
        if not self._items:
            return None
        self.head = (self.head + 1) & 0xFFFFFFFF
        return self._items.popleft()

    def __len__(self) -> int:
        return len(self._items)


class RcifDevice:
    """Behavioral model of registers, rings, scheduler boundary, and KV MMU."""

    ID = 0x52434946
    VERSION = 0x00010000

    def __init__(self, otp_minimum_version: int = 1):
        self.otp_minimum_version = otp_minimum_version
        self.counters = {counter: 0 for counter in Counter}
        self.debug_locked = False
        self.power_on_reset()

    def power_on_reset(self) -> None:
        self.status = DeviceStatus.BOOT_ROM
        self.secure_verified = False
        self.boot_failed = False
        self.debug_locked = False
        self.firmware_version = 0
        self.enabled = False
        self.command_ring: Optional[Ring[Command]] = None
        self.completion_ring: Optional[Ring[Completion]] = None
        self.fault_ring: Optional[Ring[Fault]] = None
        self._pending: Dict[int, Command] = {}
        self.kv_pages: Dict[int, int] = {}

    def warm_reset(self) -> None:
        """Reset mutable engines while retaining security state and OTP state."""
        locked = self.debug_locked
        version = self.firmware_version
        verified = self.secure_verified
        self.enabled = False
        self.status = DeviceStatus.FIRMWARE_READY if verified else DeviceStatus.BOOT_ROM
        self.command_ring = None
        self.completion_ring = None
        self.fault_ring = None
        self._pending = {}
        self.debug_locked = locked
        self.firmware_version = version

    def initialize_queues(self, entries: int = 16) -> None:
        self.command_ring = Ring(entries)
        self.completion_ring = Ring(entries)
        self.fault_ring = Ring(entries)

    def enable(self) -> None:
        if not self.secure_verified or self.boot_failed:
            raise PermissionError("queue processing requires authenticated firmware")
        if any(
            ring is None
            for ring in (self.command_ring, self.completion_ring, self.fault_ring)
        ):
            raise RuntimeError("all queues must be initialized before enable")
        self.enabled = True
        self.status = DeviceStatus.RUNNING

    def submit(self, command: Command) -> bool:
        if not self.enabled or self.command_ring is None:
            raise RuntimeError("device is not running")
        accepted = self.command_ring.push(command)
        if not accepted:
            self._increment(Counter.QUEUE_ERRORS)
        return accepted

    def process(self, budget: Optional[int] = None) -> int:
        if not self.enabled or self.command_ring is None:
            return 0
        processed = 0
        while budget is None or processed < budget:
            command = self.command_ring.pop()
            if command is None:
                break
            self._increment(Counter.ACCEPTED)
            self._execute(command)
            processed += 1
        return processed

    def replay(self, request_id: int) -> bool:
        command = self._pending.pop(request_id, None)
        if command is None or command.retry_count >= 3:
            return False
        replayed = Command(
            request_id=command.request_id,
            opcode=command.opcode,
            graph=command.graph,
            priority=command.priority,
            argument=command.argument,
            flags=command.flags,
            retry_count=command.retry_count + 1,
        )
        self._execute(replayed, count_accept=False)
        return True

    def read_counter(self, selector: int) -> int:
        try:
            return self.counters[Counter(selector)]
        except ValueError:
            raise ValueError("unsupported performance counter {}".format(selector))

    def _execute(self, command: Command, count_accept: bool = True) -> None:
        del count_accept
        if command.flags:
            self._complete(Completion(command.request_id, Status.BAD_FLAGS))
        elif command.opcode == CommandOpcode.SUBMIT_GRAPH:
            self._execute_graph(command)
        elif command.opcode == CommandOpcode.KV_TRANSLATE:
            self._translate(command)
        else:
            self._complete(Completion(command.request_id, Status.UNSUPPORTED))

    def _execute_graph(self, command: Command) -> None:
        graph = command.graph
        if not graph or len(graph) > 8 or not 0 <= command.priority <= 3:
            self._complete(Completion(command.request_id, Status.GRAPH_INVALID))
            return
        self._increment(Counter.GRAPH_NODES, len(graph))
        complete_mask = 0
        result = 0
        remaining = list(graph)
        while remaining:
            progressed = False
            for node in tuple(remaining):
                if node.node_id > 7 or node.dependencies & ~complete_mask:
                    continue
                if node.opcode == GraphOpcode.NOP:
                    result ^= node.operand0
                    complete_mask |= 1 << node.node_id
                    remaining.remove(node)
                    progressed = True
                    break
                if node.opcode == GraphOpcode.COMPLETE:
                    self._complete(
                        Completion(command.request_id, Status.OK, (result ^ node.operand0) & MASK64)
                    )
                    return
                self._complete(Completion(command.request_id, Status.GRAPH_INVALID, node.opcode))
                return
            if not progressed:
                self._complete(Completion(command.request_id, Status.GRAPH_DEADLOCK, complete_mask))
                return
        self._complete(Completion(command.request_id, Status.GRAPH_INVALID, complete_mask))

    def _translate(self, command: Command) -> None:
        page = command.argument
        if page in self.kv_pages:
            self._complete(Completion(command.request_id, Status.OK, self.kv_pages[page]))
            return
        fault = Fault(command.request_id, page, Status.KV_MISS, retry_count=command.retry_count)
        self._pending[command.request_id] = command
        self._increment(Counter.KV_FAULTS)
        if self.fault_ring is None or not self.fault_ring.push(fault):
            self._increment(Counter.FAULT_OVERFLOWS)
            self._pending.pop(command.request_id, None)
            self._complete(Completion(command.request_id, Status.KV_MISS, page))

    def _complete(self, completion: Completion) -> None:
        if self.completion_ring is None or not self.completion_ring.push(completion):
            self._increment(Counter.QUEUE_ERRORS)
            self.status = DeviceStatus.FATAL
            self.enabled = False
            return
        self._increment(Counter.COMPLETED)
        if completion.status != Status.OK:
            self._increment(Counter.ERRORS)

    def _increment(self, counter: Counter, amount: int = 1) -> None:
        self.counters[counter] = min(MASK64, self.counters[counter] + amount)
