"""Host-facing RCIF driver prototype."""

from typing import Dict, Iterable, Optional

from .device import RcifDevice
from .firmware import FirmwareController
from .protocol import Command, CommandOpcode, Completion, GraphNode


class RcifDriver:
    def __init__(self, device: RcifDevice, firmware: FirmwareController):
        self.device = device
        self.firmware = firmware
        self._next_request_id = 1
        self._completions: Dict[int, Completion] = {}

    def probe(self) -> None:
        if self.device.ID != 0x52434946 or self.device.VERSION >> 16 != 1:
            raise RuntimeError("unsupported RCIF device")
        if not self.device.enabled:
            raise RuntimeError("RCIF firmware is not running")

    def submit_graph(self, nodes: Iterable[GraphNode], priority: int = 0) -> int:
        graph = tuple(nodes)
        for node in graph:
            # Encoding performs the same width/reserved-bit validation as a real ioctl.
            node.encode()
        request_id = self._allocate_request_id()
        command = Command(request_id, CommandOpcode.SUBMIT_GRAPH, graph, priority)
        if not self.device.submit(command):
            raise BlockingIOError("command ring is full")
        return request_id

    def translate_kv(self, virtual_page: int) -> int:
        if virtual_page < 0 or virtual_page >= 1 << 64:
            raise ValueError("virtual page must be an unsigned 64-bit value")
        request_id = self._allocate_request_id()
        command = Command(
            request_id=request_id,
            opcode=CommandOpcode.KV_TRANSLATE,
            argument=virtual_page,
        )
        if not self.device.submit(command):
            raise BlockingIOError("command ring is full")
        return request_id

    def poll(self, service_firmware: bool = True) -> int:
        self.device.process()
        if service_firmware:
            self.firmware.service_faults()
        drained = 0
        if self.device.completion_ring is not None:
            while True:
                completion = self.device.completion_ring.pop()
                if completion is None:
                    break
                self._completions[completion.request_id] = completion
                drained += 1
        return drained

    def completion(self, request_id: int) -> Optional[Completion]:
        return self._completions.pop(request_id, None)

    def wait(self, request_id: int, polls: int = 16) -> Completion:
        for _ in range(polls):
            self.poll()
            completion = self.completion(request_id)
            if completion is not None:
                return completion
        raise TimeoutError("request {} did not complete".format(request_id))

    def read_counter(self, selector: int) -> int:
        return self.device.read_counter(selector)

    def _allocate_request_id(self) -> int:
        request_id = self._next_request_id
        self._next_request_id = (self._next_request_id + 1) & ((1 << 64) - 1)
        if self._next_request_id == 0:
            self._next_request_id = 1
        return request_id

