#ifndef RCIF_KV_FAULT_H
#define RCIF_KV_FAULT_H

#include <stdbool.h>
#include <stdint.h>

#define RCIF_FAULT_REPLAYABLE (1u << 0)

struct rcif_fault_entry {
  uint64_t request_id;
  uint64_t address;
  uint16_t cause;
  uint8_t engine;
  uint8_t retry_count;
  uint32_t flags;
  uint64_t reserved;
};

typedef bool (*rcif_map_page_fn)(uint64_t virtual_page, uint64_t *physical_page,
                                 void *context);
typedef bool (*rcif_replay_fn)(uint64_t request_id, void *context);

bool rcif_handle_kv_fault(const struct rcif_fault_entry *fault,
                          rcif_map_page_fn map_page, rcif_replay_fn replay,
                          void *context);

#endif
