#ifndef RCIF_TELEMETRY_H
#define RCIF_TELEMETRY_H

#include <stdint.h>

uint64_t rcif_counter_read(uintptr_t mmio, uint32_t selector);

#endif
