#ifndef RCIF_BOOT_H
#define RCIF_BOOT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "../drivers/rcif_queue.h"

#define RCIF_MANIFEST_MAGIC 0x52434657u

struct rcif_firmware_manifest {
  uint32_t magic;
  uint32_t header_bytes;
  uint32_t image_bytes;
  uint32_t security_version;
  uint8_t digest[32];
  uint8_t signature[64];
};

struct rcif_boot_services {
  bool (*verify_image)(const struct rcif_firmware_manifest *manifest,
                       const uint8_t *image, void *context);
  uint32_t (*minimum_security_version)(void *context);
  void (*record_security_version)(uint32_t version, void *context);
  void *context;
};

struct rcif_boot_config {
  uintptr_t mmio;
  struct rcif_queue_config command_queue;
  struct rcif_queue_config completion_queue;
  struct rcif_queue_config fault_queue;
  bool lock_debug;
};

enum rcif_boot_result {
  RCIF_BOOT_OK = 0,
  RCIF_BOOT_BAD_MANIFEST = 1,
  RCIF_BOOT_ROLLBACK = 2,
  RCIF_BOOT_AUTH_FAILURE = 3,
  RCIF_BOOT_BAD_QUEUE = 4,
};

enum rcif_boot_result rcif_firmware_boot(
    const struct rcif_firmware_manifest *manifest, const uint8_t *image,
    const struct rcif_boot_services *services,
    const struct rcif_boot_config *config);

#endif
