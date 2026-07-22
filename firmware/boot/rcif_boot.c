#include "rcif_boot.h"

#include "../include/rcif_registers.h"

static enum rcif_boot_result fail(uintptr_t mmio,
                                  enum rcif_boot_result result) {
  rcif_mmio_write32(mmio, RCIF_REG_CONTROL, 0u);
  rcif_mmio_write32(mmio, RCIF_REG_SECURE_STATUS, RCIF_SECURE_BOOT_FAILED);
  rcif_mmio_write32(mmio, RCIF_REG_STATUS, RCIF_STATUS_FATAL);
  return result;
}

enum rcif_boot_result rcif_firmware_boot(
    const struct rcif_firmware_manifest *manifest, const uint8_t *image,
    const struct rcif_boot_services *services,
    const struct rcif_boot_config *config) {
  if (manifest == 0 || image == 0 || services == 0 || config == 0 ||
      services->verify_image == 0 || services->minimum_security_version == 0 ||
      services->record_security_version == 0) {
    return RCIF_BOOT_BAD_MANIFEST;
  }
  if (manifest->magic != RCIF_MANIFEST_MAGIC ||
      manifest->header_bytes != sizeof(*manifest) ||
      manifest->image_bytes == 0u) {
    return fail(config->mmio, RCIF_BOOT_BAD_MANIFEST);
  }
  if (manifest->security_version <
      services->minimum_security_version(services->context)) {
    return fail(config->mmio, RCIF_BOOT_ROLLBACK);
  }
  if (!services->verify_image(manifest, image, services->context)) {
    return fail(config->mmio, RCIF_BOOT_AUTH_FAILURE);
  }

  if (!rcif_queue_init(config->mmio, RCIF_QUEUE_COMMAND,
                       &config->command_queue) ||
      !rcif_queue_init(config->mmio, RCIF_QUEUE_COMPLETION,
                       &config->completion_queue) ||
      !rcif_queue_init(config->mmio, RCIF_QUEUE_FAULT,
                       &config->fault_queue)) {
    return fail(config->mmio, RCIF_BOOT_BAD_QUEUE);
  }

  services->record_security_version(manifest->security_version,
                                    services->context);
  rcif_mmio_write32(config->mmio, RCIF_REG_FW_VERSION,
                    manifest->security_version);
  rcif_mmio_write32(config->mmio, RCIF_REG_SECURE_STATUS,
                    RCIF_SECURE_VERIFIED | RCIF_SECURE_ROLLBACK_OK |
                        (config->lock_debug ? RCIF_SECURE_LOCKED : 0u));
  rcif_mmio_write32(config->mmio, RCIF_REG_STATUS,
                    RCIF_STATUS_FIRMWARE_READY);
  if (config->lock_debug) {
    rcif_mmio_write32(config->mmio, RCIF_REG_SECURE_CFG,
                      RCIF_SECURE_DEBUG_LOCK);
  }
  rcif_mmio_write32(config->mmio, RCIF_REG_CONTROL, RCIF_CONTROL_ENABLE);
  rcif_mmio_write32(config->mmio, RCIF_REG_STATUS, RCIF_STATUS_RUNNING);
  return RCIF_BOOT_OK;
}
