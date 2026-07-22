#include "rcif_kv_fault.h"

bool rcif_handle_kv_fault(const struct rcif_fault_entry *fault,
                          rcif_map_page_fn map_page, rcif_replay_fn replay,
                          void *context) {
  uint64_t physical_page = 0;
  if (fault == 0 || map_page == 0 || replay == 0) return false;
  if ((fault->flags & RCIF_FAULT_REPLAYABLE) == 0u) return false;
  if (fault->retry_count >= 3u) return false;
  if (!map_page(fault->address, &physical_page, context)) return false;
  (void)physical_page;
  return replay(fault->request_id, context);
}
