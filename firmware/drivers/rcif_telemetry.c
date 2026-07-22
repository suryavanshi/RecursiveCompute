#include "rcif_telemetry.h"

#include "../include/rcif_registers.h"

uint64_t rcif_counter_read(uintptr_t mmio, uint32_t selector) {
  rcif_mmio_write32(mmio, RCIF_REG_PERF_SELECT, selector);
  const uint32_t low = rcif_mmio_read32(mmio, RCIF_REG_PERF_DATA_LO);
  const uint32_t high = rcif_mmio_read32(mmio, RCIF_REG_PERF_DATA_HI);
  return ((uint64_t)high << 32) | low;
}
