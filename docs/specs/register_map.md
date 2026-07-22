# RCIF Control-Plane Register Map

This document freezes the Phase 8 firmware/driver interface. Registers are
little-endian, naturally aligned, and 32 bits wide unless noted otherwise.
Queue payloads are little-endian and live in host-coherent memory. A 64-bit
register is written low word then high word and is only consumed after the
corresponding queue `SIZE` register is enabled.

## Global registers

| Offset | Name | Access | Reset | Description |
| ---: | --- | --- | ---: | --- |
| `0x000` | `ID` | RO | `0x52434946` | ASCII `RCIF`. |
| `0x004` | `VERSION` | RO | `0x00010000` | Major 1, minor 0. |
| `0x008` | `CAPABILITIES` | RO | `0x0000001f` | Command/completion/fault rings, secure boot, telemetry. |
| `0x00c` | `STATUS` | RO to host | `1` | Firmware-owned boot and fatal state, defined below. |
| `0x010` | `CONTROL` | RW | `0` | Bit 0 enables queue processing; bit 1 requests a warm reset. |
| `0x014` | `DOORBELL` | WO | `0` | Write the command producer index after publishing descriptors. |
| `0x018` | `IRQ_STATUS` | RW1C | `0` | Completion, fault, fatal, and telemetry-overflow events. |
| `0x01c` | `IRQ_MASK` | RW | `0` | One enables the corresponding interrupt. |
| `0x020` | `FAULT_ADDR_LO` | RO | `0` | Virtual page/address of the most recent fault. |
| `0x024` | `FAULT_ADDR_HI` | RO | `0` | Upper fault address bits. |
| `0x028` | `FAULT_INFO` | RO | `0` | Cause `[7:0]`, engine `[15:8]`, request id low `[31:16]`. |
| `0x030` | `PERF_SELECT` | RW | `0` | Counter selector. Writing latches the selected 64-bit value. |
| `0x034` | `PERF_DATA_LO` | RO | `0` | Latched counter low word. |
| `0x038` | `PERF_DATA_HI` | RO | `0` | Latched counter high word. |
| `0x040` | `SECURE_CFG` | RW1S | `0` | Bit 0 permanently locks external debug until power-on reset. |
| `0x044` | `SECURE_STATUS` | RO to host | `0` | ROM/firmware-owned verified, debug-locked, anti-rollback-ok, and boot-failed bits. |
| `0x048` | `FW_VERSION` | RO to host | `0` | Firmware-owned authenticated security version. |

`STATUS` values are `1=BOOT_ROM`, `2=FIRMWARE_READY`, `3=RUNNING`, and
`0x80000000=FATAL`. Queue processing is permitted only in `RUNNING` after the
boot image has authenticated. Warm reset preserves the debug lock and minimum
security version; power-on reset is required to clear the lock.

## Queue register blocks

Command, completion, and fault rings use identical blocks at `0x100`, `0x140`,
and `0x180` respectively.

| Relative offset | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x00` | `BASE_LO` | RW | 64-byte-aligned coherent ring base. |
| `0x04` | `BASE_HI` | RW | Upper base bits. |
| `0x08` | `SIZE` | RW | Power-of-two entries, 4 through 1024; zero disables. |
| `0x0c` | `HEAD` | mixed | Consumer monotonically incremented index. |
| `0x10` | `TAIL` | mixed | Producer monotonically incremented index. |

The host produces commands and consumes completions. Firmware/hardware consume
commands and produce completions and faults. Producers write the complete entry,
execute a release fence, update `TAIL`, then ring the applicable doorbell.
Consumers acquire `TAIL` before reading entries and publish `HEAD` after use.
Full and empty are determined from unbounded 32-bit index subtraction; a
producer must never advance by more than `SIZE` beyond the consumer.

## Queue entries

All entries are 32 bytes. Reserved fields must be zero.

Command entry:

| Bytes | Field | Description |
| ---: | --- | --- |
| `0..7` | request id | Unique while outstanding. |
| `8..15` | graph address | 16-byte-aligned address of 128-bit graph nodes. |
| `16..17` | graph nodes | 1 through 8. |
| `18` | priority | 0 through 3. |
| `19` | opcode | `1=SUBMIT_GRAPH`, `2=KV_TRANSLATE`. |
| `20..23` | flags | Must be zero in version 1. |
| `24..31` | argument | KV virtual page for `KV_TRANSLATE`; zero otherwise. |

Completion entry contains request id at bytes `0..7`, 32-bit status at
`8..11`, and a 64-bit result at `16..23`. Fault entries contain request id,
64-bit virtual page/address, cause, engine id, retry count, and flags. Fault
flag bit 0 means firmware may install a mapping and replay the command.

Graph nodes use the 128-bit format in `token_graph_descriptor.md`. The host must
keep graph memory pinned until its completion is consumed.

## Performance counters

| Selector | Counter |
| ---: | --- |
| `0` | accepted commands |
| `1` | completed commands |
| `2` | command/fatal errors |
| `3` | fault-ring overflows |
| `4` | KV page faults |
| `5` | KV faults recovered and replayed |
| `6` | boot attempts |
| `7` | boot authentication failures |
| `8` | submitted graph nodes |
| `9` | queue protocol errors |

Counter values saturate at `2^64-1`. `PERF_SELECT` latches both halves so a
rollover cannot tear a software read.

## Secure boot contract

Immutable ROM validates manifest magic, bounds, SHA-256 digest, signature, and
the image security version against OTP rollback state. Signature verification
is supplied by a ROM/platform service so mutable firmware never owns the root
key. Only then may firmware initialize queues, set `FIRMWARE_READY`, lock debug,
and enable processing. Authentication failure sets `BOOT_FAILED|FATAL`, leaves
queues disabled, and cannot be bypassed by a warm reset.
