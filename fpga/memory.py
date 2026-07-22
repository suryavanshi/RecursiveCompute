"""External-memory proxy used by the Phase 10 FPGA/emulation prototype."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class MemoryTiming:
    clock_hz: int = 100_000_000
    local_read_cycles: int = 12
    host_read_cycles: int = 80
    migration_setup_cycles: int = 24
    bytes_per_cycle: int = 16

    def migration_cycles(self, size_bytes: int) -> int:
        beats = (size_bytes + self.bytes_per_cycle - 1) // self.bytes_per_cycle
        return self.migration_setup_cycles + self.host_read_cycles + beats


@dataclass
class Page:
    virtual_page: int
    payload: Any
    size_bytes: int
    tier: str
    physical_page: int


class ExternalMemory:
    """A deterministic DDR/HBM proxy with host-tier migration.

    The payload is deliberately typed as an object: RTL sees bytes, while the
    emulation backend keeps structured K/V tensors to avoid a framework
    dependency.  Size and cycle accounting always use the serialized byte size.
    """

    def __init__(self, local_pages: int = 32, timing: MemoryTiming | None = None):
        if local_pages <= 0:
            raise ValueError("local_pages must be positive")
        self.local_pages = local_pages
        self.timing = timing or MemoryTiming()
        self.pages: dict[int, Page] = {}
        self._next_physical = 0
        self.page_faults = 0
        self.migrations = 0
        self.bytes_migrated = 0

    def map_page(
        self, virtual_page: int, payload: Any, size_bytes: int, *, tier: str = "host"
    ) -> None:
        if virtual_page < 0 or size_bytes <= 0:
            raise ValueError("page id and size must be positive")
        if tier not in {"local", "host"}:
            raise ValueError("tier must be local or host")
        if tier == "local" and self.local_resident >= self.local_pages:
            raise MemoryError("local DDR proxy is full")
        physical = self._allocate_physical() if tier == "local" else -1
        self.pages[virtual_page] = Page(
            virtual_page, payload, size_bytes, tier, physical
        )

    @property
    def local_resident(self) -> int:
        return sum(page.tier == "local" for page in self.pages.values())

    def ensure_local(self, virtual_page: int) -> tuple[Page, int, bool]:
        try:
            page = self.pages[virtual_page]
        except KeyError as error:
            self.page_faults += 1
            raise KeyError("unmapped virtual page {}".format(virtual_page)) from error
        if page.tier == "local":
            return page, self.timing.local_read_cycles, False

        self.page_faults += 1
        if self.local_resident >= self.local_pages:
            # Deterministic first-page eviction keeps replay cycle-stable.
            victim = min(
                item.virtual_page for item in self.pages.values() if item.tier == "local"
            )
            victim_page = self.pages[victim]
            victim_page.tier = "host"
            victim_page.physical_page = -1
        page.tier = "local"
        page.physical_page = self._allocate_physical()
        self.migrations += 1
        self.bytes_migrated += page.size_bytes
        return page, self.timing.migration_cycles(page.size_bytes), True

    def _allocate_physical(self) -> int:
        value = self._next_physical
        self._next_physical += 1
        return value
