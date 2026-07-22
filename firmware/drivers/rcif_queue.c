#include "rcif_queue.h"

#include "../include/rcif_registers.h"

bool rcif_queue_config_valid(const struct rcif_queue_config *config) {
  if (config == NULL || config->base == 0u || (config->base & 63u) != 0u)
    return false;
  if (config->entries < 4u || config->entries > 1024u) return false;
  return (config->entries & (config->entries - 1u)) == 0u;
}

bool rcif_queue_init(uintptr_t mmio, uint32_t queue_offset,
                     const struct rcif_queue_config *config) {
  if (!rcif_queue_config_valid(config)) return false;
  rcif_mmio_write32(mmio, queue_offset + RCIF_QUEUE_SIZE, 0u);
  rcif_mmio_write32(mmio, queue_offset + RCIF_QUEUE_BASE_LO,
                    (uint32_t)config->base);
  rcif_mmio_write32(mmio, queue_offset + RCIF_QUEUE_BASE_HI,
                    (uint32_t)(config->base >> 32));
  rcif_mmio_write32(mmio, queue_offset + RCIF_QUEUE_HEAD, 0u);
  rcif_mmio_write32(mmio, queue_offset + RCIF_QUEUE_TAIL, 0u);
  rcif_io_fence();
  rcif_mmio_write32(mmio, queue_offset + RCIF_QUEUE_SIZE, config->entries);
  return true;
}
