#ifndef RCIF_REGISTERS_H
#define RCIF_REGISTERS_H

#include <stdint.h>

#define RCIF_REG_ID                 0x000u
#define RCIF_REG_VERSION            0x004u
#define RCIF_REG_CAPABILITIES       0x008u
#define RCIF_REG_STATUS             0x00cu
#define RCIF_REG_CONTROL            0x010u
#define RCIF_REG_DOORBELL           0x014u
#define RCIF_REG_IRQ_STATUS         0x018u
#define RCIF_REG_IRQ_MASK           0x01cu
#define RCIF_REG_FAULT_ADDR_LO      0x020u
#define RCIF_REG_FAULT_ADDR_HI      0x024u
#define RCIF_REG_FAULT_INFO         0x028u
#define RCIF_REG_PERF_SELECT        0x030u
#define RCIF_REG_PERF_DATA_LO       0x034u
#define RCIF_REG_PERF_DATA_HI       0x038u
#define RCIF_REG_SECURE_CFG         0x040u
#define RCIF_REG_SECURE_STATUS      0x044u
#define RCIF_REG_FW_VERSION         0x048u

#define RCIF_QUEUE_COMMAND          0x100u
#define RCIF_QUEUE_COMPLETION       0x140u
#define RCIF_QUEUE_FAULT            0x180u
#define RCIF_QUEUE_BASE_LO          0x00u
#define RCIF_QUEUE_BASE_HI          0x04u
#define RCIF_QUEUE_SIZE             0x08u
#define RCIF_QUEUE_HEAD             0x0cu
#define RCIF_QUEUE_TAIL             0x10u

#define RCIF_STATUS_BOOT_ROM        1u
#define RCIF_STATUS_FIRMWARE_READY  2u
#define RCIF_STATUS_RUNNING         3u
#define RCIF_STATUS_FATAL           0x80000000u
#define RCIF_CONTROL_ENABLE         (1u << 0)
#define RCIF_CONTROL_WARM_RESET     (1u << 1)
#define RCIF_SECURE_DEBUG_LOCK      (1u << 0)
#define RCIF_SECURE_VERIFIED        (1u << 0)
#define RCIF_SECURE_LOCKED          (1u << 1)
#define RCIF_SECURE_ROLLBACK_OK     (1u << 2)
#define RCIF_SECURE_BOOT_FAILED     (1u << 3)

#define RCIF_PERF_ACCEPTED          0u
#define RCIF_PERF_COMPLETED         1u
#define RCIF_PERF_ERRORS            2u
#define RCIF_PERF_FAULT_OVERFLOWS   3u
#define RCIF_PERF_KV_FAULTS         4u
#define RCIF_PERF_KV_RECOVERED      5u
#define RCIF_PERF_BOOT_ATTEMPTS     6u
#define RCIF_PERF_BOOT_FAILURES     7u
#define RCIF_PERF_GRAPH_NODES       8u
#define RCIF_PERF_QUEUE_ERRORS      9u

static inline void rcif_mmio_write32(uintptr_t base, uint32_t offset, uint32_t value) {
  *(volatile uint32_t *)(base + offset) = value;
}

static inline uint32_t rcif_mmio_read32(uintptr_t base, uint32_t offset) {
  return *(volatile const uint32_t *)(base + offset);
}

static inline void rcif_io_fence(void) {
#if defined(__riscv)
  __asm__ volatile("fence iorw, iorw" ::: "memory");
#else
  __asm__ volatile("" ::: "memory");
#endif
}

#endif
