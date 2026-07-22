#include <stdbool.h>
#include <stdint.h>

#include "firmware/boot/rcif_boot.h"
#include "firmware/drivers/rcif_kv_fault.h"
#include "firmware/include/rcif_registers.h"

struct rom_context {
  uint32_t minimum_version;
  uint32_t recorded_version;
  bool accept_signature;
  bool replayed;
};

static bool verify_image(const struct rcif_firmware_manifest *manifest,
                         const uint8_t *image, void *opaque) {
  struct rom_context *context = opaque;
  return context->accept_signature && manifest->image_bytes == 4u &&
         image[0] == 0x13u;
}

static uint32_t minimum_version(void *opaque) {
  return ((struct rom_context *)opaque)->minimum_version;
}

static void record_version(uint32_t version, void *opaque) {
  ((struct rom_context *)opaque)->recorded_version = version;
}

static bool map_page(uint64_t virtual_page, uint64_t *physical_page,
                     void *opaque) {
  (void)opaque;
  if (virtual_page != 0x55u) return false;
  *physical_page = 0x1000u;
  return true;
}

static bool replay(uint64_t request_id, void *opaque) {
  struct rom_context *context = opaque;
  context->replayed = request_id == 7u;
  return context->replayed;
}

int main(void) {
  uint32_t registers[0x200u / sizeof(uint32_t)] = {0};
  const uint8_t image[4] = {0x13u, 0u, 0u, 0u};
  const struct rcif_firmware_manifest manifest = {
      .magic = RCIF_MANIFEST_MAGIC,
      .header_bytes = sizeof(struct rcif_firmware_manifest),
      .image_bytes = sizeof(image),
      .security_version = 3u,
  };
  struct rom_context context = {
      .minimum_version = 2u,
      .accept_signature = true,
  };
  const struct rcif_boot_services services = {
      .verify_image = verify_image,
      .minimum_security_version = minimum_version,
      .record_security_version = record_version,
      .context = &context,
  };
  const struct rcif_boot_config config = {
      .mmio = (uintptr_t)registers,
      .command_queue = {.base = 0x1000u, .entries = 8u},
      .completion_queue = {.base = 0x2000u, .entries = 8u},
      .fault_queue = {.base = 0x3000u, .entries = 8u},
      .lock_debug = true,
  };

  if (rcif_firmware_boot(&manifest, image, &services, &config) != RCIF_BOOT_OK)
    return 1;
  if (registers[RCIF_REG_STATUS / 4u] != RCIF_STATUS_RUNNING) return 2;
  if (registers[RCIF_REG_CONTROL / 4u] != RCIF_CONTROL_ENABLE) return 3;
  if (registers[(RCIF_QUEUE_COMMAND + RCIF_QUEUE_SIZE) / 4u] != 8u) return 4;
  if (registers[(RCIF_QUEUE_COMPLETION + RCIF_QUEUE_SIZE) / 4u] != 8u) return 5;
  if (registers[(RCIF_QUEUE_FAULT + RCIF_QUEUE_SIZE) / 4u] != 8u) return 6;
  if (registers[RCIF_REG_SECURE_CFG / 4u] != RCIF_SECURE_DEBUG_LOCK) return 7;
  if (context.recorded_version != 3u) return 8;
  if (registers[RCIF_REG_SECURE_STATUS / 4u] !=
      (RCIF_SECURE_VERIFIED | RCIF_SECURE_ROLLBACK_OK | RCIF_SECURE_LOCKED))
    return 14;

  const struct rcif_fault_entry fault = {
      .request_id = 7u,
      .address = 0x55u,
      .cause = 4u,
      .retry_count = 0u,
      .flags = RCIF_FAULT_REPLAYABLE,
  };
  if (!rcif_handle_kv_fault(&fault, map_page, replay, &context)) return 9;
  if (!context.replayed) return 10;

  context.accept_signature = false;
  if (rcif_firmware_boot(&manifest, image, &services, &config) !=
      RCIF_BOOT_AUTH_FAILURE)
    return 11;
  if (registers[RCIF_REG_STATUS / 4u] != RCIF_STATUS_FATAL) return 12;
  if (registers[RCIF_REG_CONTROL / 4u] != 0u) return 13;
  if (registers[RCIF_REG_SECURE_STATUS / 4u] != RCIF_SECURE_BOOT_FAILED)
    return 15;
  return 0;
}
