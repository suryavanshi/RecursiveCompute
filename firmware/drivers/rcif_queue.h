#ifndef RCIF_QUEUE_H
#define RCIF_QUEUE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct rcif_queue_config {
  uint64_t base;
  uint32_t entries;
};

bool rcif_queue_config_valid(const struct rcif_queue_config *config);
bool rcif_queue_init(uintptr_t mmio, uint32_t queue_offset,
                     const struct rcif_queue_config *config);

#endif
