#include <cstdint>
#include <iostream>

#include "Vrcif_top.h"
#include "verilated.h"

namespace {

constexpr uint16_t kOpcodeNop = 0x0000;
constexpr uint16_t kOpcodeEcho = 0x0001;
constexpr uint16_t kOpcodeGetCounter = 0x0010;
constexpr uint16_t kOpcodeKvMap = 0x0020;
constexpr uint16_t kOpcodeKvTranslate = 0x0021;
constexpr uint16_t kOpcodeDmaCopy = 0x0030;
constexpr uint32_t kStatusOk = 0;
constexpr uint32_t kStatusUnsupportedOpcode = 1;
constexpr uint32_t kStatusUnsupportedFlags = 2;
constexpr uint32_t kStatusUnsupportedCounter = 3;
constexpr uint32_t kStatusKvMiss = 4;
constexpr uint32_t kStatusKvFull = 5;
constexpr uint32_t kStatusKvReservedBits = 6;
constexpr uint32_t kStatusDmaZeroLength = 7;
constexpr uint32_t kStatusDmaReservedBits = 8;
constexpr uint32_t kStatusDmaRange = 9;
constexpr uint8_t kCounterAccepted = 0;
constexpr uint8_t kCounterCompleted = 1;
constexpr uint8_t kCounterErrors = 2;

uint64_t pack_kv_entry(uint16_t virt_page, uint16_t phys_page, uint8_t tier, uint8_t format) {
  return static_cast<uint64_t>(virt_page) |
         (static_cast<uint64_t>(phys_page) << 16) |
         (static_cast<uint64_t>(tier & 0xf) << 32) |
         (static_cast<uint64_t>(format & 0xf) << 36);
}

uint64_t pack_dma_desc(uint16_t src_page, uint16_t dst_page, uint16_t length) {
  return static_cast<uint64_t>(src_page) |
         (static_cast<uint64_t>(dst_page) << 16) |
         (static_cast<uint64_t>(length) << 32);
}

uint64_t dma_page_seed(uint16_t page) {
  return 0x9e3779b97f4a7c15ULL ^ static_cast<uint64_t>(page);
}

uint64_t dma_copy_checksum(uint16_t src_page, uint16_t length) {
  uint64_t checksum = 0;
  for (uint16_t offset = 0; offset < length; ++offset) {
    checksum ^= dma_page_seed(src_page + offset);
  }
  return checksum;
}

void tick(Vrcif_top& top) {
  top.clk_i = 0;
  top.eval();
  top.clk_i = 1;
  top.eval();
}

void reset(Vrcif_top& top) {
  top.rst_ni = 0;
  top.cmd_valid_i = 0;
  top.cpl_ready_i = 1;
  top.cmd_request_id_i = 0;
  top.cmd_opcode_i = 0;
  top.cmd_flags_i = 0;
  top.cmd_payload_i = 0;
  tick(top);
  tick(top);
  top.rst_ni = 1;
  tick(top);
}

bool wait_completion(
    Vrcif_top& top,
    uint32_t request_id,
    uint32_t status,
    uint64_t result,
    int max_cycles = 16) {
  for (int cycle = 0; cycle < max_cycles; ++cycle) {
    top.eval();
    if (top.cpl_valid_o) {
      const bool ok = top.cpl_request_id_o == request_id &&
                      top.cpl_status_o == status &&
                      top.cpl_result_o == result;
      tick(top);
      return ok;
    }
    tick(top);
  }
  return false;
}

bool send_command(
    Vrcif_top& top,
    uint32_t request_id,
    uint16_t opcode,
    uint16_t flags,
    uint64_t payload,
    uint32_t expected_status,
    uint64_t expected_result) {
  top.eval();
  if (!top.cmd_ready_o) {
    std::cerr << "command interface not ready before send\n";
    return false;
  }

  top.cmd_valid_i = 1;
  top.cmd_request_id_i = request_id;
  top.cmd_opcode_i = opcode;
  top.cmd_flags_i = flags;
  top.cmd_payload_i = payload;
  tick(top);
  top.cmd_valid_i = 0;

  return wait_completion(top, request_id, expected_status, expected_result);
}

bool send_echo(Vrcif_top& top, uint32_t request_id, uint64_t payload) {
  return send_command(top, request_id, kOpcodeEcho, 0, payload, kStatusOk, payload);
}

bool enqueue_command(
    Vrcif_top& top,
    uint32_t request_id,
    uint16_t opcode,
    uint16_t flags,
    uint64_t payload) {
  top.eval();
  if (!top.cmd_ready_o) {
    std::cerr << "command interface not ready during enqueue\n";
    return false;
  }
  top.cmd_valid_i = 1;
  top.cmd_request_id_i = request_id;
  top.cmd_opcode_i = opcode;
  top.cmd_flags_i = flags;
  top.cmd_payload_i = payload;
  tick(top);
  top.cmd_valid_i = 0;
  return true;
}

bool send_get_counter(
    Vrcif_top& top,
    uint32_t request_id,
    uint8_t counter_id,
    uint32_t expected_status,
    uint64_t expected_result) {
  return send_command(
      top,
      request_id,
      kOpcodeGetCounter,
      0,
      counter_id,
      expected_status,
      expected_result);
}

bool check_completion_backpressure(Vrcif_top& top) {
  top.cpl_ready_i = 0;
  top.cmd_valid_i = 1;
  top.cmd_request_id_i = 0x55;
  top.cmd_opcode_i = kOpcodeEcho;
  top.cmd_flags_i = 0;
  top.cmd_payload_i = 0x12345678ULL;
  tick(top);
  top.cmd_valid_i = 0;

  bool saw_valid = false;
  for (int cycle = 0; cycle < 4; ++cycle) {
    top.eval();
    saw_valid = saw_valid || top.cpl_valid_o;
    if (top.cpl_valid_o &&
        (top.cpl_request_id_o != 0x55 ||
         top.cpl_status_o != kStatusOk ||
         top.cpl_result_o != 0x12345678ULL)) {
      return false;
    }
    tick(top);
  }

  top.cpl_ready_i = 1;
  const bool drained = wait_completion(top, 0x55, kStatusOk, 0x12345678ULL, 2);
  return saw_valid && drained;
}

bool check_burst_queueing(Vrcif_top& top) {
  top.cpl_ready_i = 0;
  for (uint32_t index = 0; index < 4; ++index) {
    if (!enqueue_command(top, 0x6000 + index, kOpcodeEcho, 0, 0xabc000 + index)) {
      return false;
    }
  }

  top.cpl_ready_i = 1;
  for (uint32_t index = 0; index < 4; ++index) {
    if (!wait_completion(top, 0x6000 + index, kStatusOk, 0xabc000 + index, 16)) {
      std::cerr << "burst completion mismatch at index " << index << "\n";
      return false;
    }
  }
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vrcif_top top;
  reset(top);

  if (!send_echo(top, 0x1234, 0xdeadbeefcafef00dULL)) {
    std::cerr << "rcif_top echo smoke failed\n";
    return 1;
  }

  if (!send_command(top, 0x2000, kOpcodeNop, 0, 0xffffULL, kStatusOk, 0)) {
    std::cerr << "rcif_top nop smoke failed\n";
    return 1;
  }

  if (!send_command(top, 0x3000, 0x00ff, 0, 0x55ULL, kStatusUnsupportedOpcode, 0x00ff)) {
    std::cerr << "rcif_top unsupported opcode smoke failed\n";
    return 1;
  }

  if (!send_command(top, 0x4000, kOpcodeEcho, 0x1, 0x55ULL, kStatusUnsupportedFlags, 0x55ULL)) {
    std::cerr << "rcif_top unsupported flags smoke failed\n";
    return 1;
  }

  if (!check_completion_backpressure(top)) {
    std::cerr << "rcif_top completion backpressure smoke failed\n";
    return 1;
  }

  if (!check_burst_queueing(top)) {
    std::cerr << "rcif_top burst queueing smoke failed\n";
    return 1;
  }

  if (!send_command(
          top,
          0x7100,
          kOpcodeKvTranslate,
          0,
          pack_kv_entry(0x0010, 0, 0, 0),
          kStatusKvMiss,
          pack_kv_entry(0x0010, 0, 0, 0))) {
    std::cerr << "rcif_top kv miss smoke failed\n";
    return 1;
  }

  if (!send_command(
          top,
          0x7101,
          kOpcodeKvMap,
          0,
          pack_kv_entry(0x0010, 0x0200, 2, 3),
          kStatusOk,
          pack_kv_entry(0x0010, 0x0200, 2, 3))) {
    std::cerr << "rcif_top kv map smoke failed\n";
    return 1;
  }

  if (!send_command(
          top,
          0x7102,
          kOpcodeKvTranslate,
          0,
          pack_kv_entry(0x0010, 0, 0, 0),
          kStatusOk,
          pack_kv_entry(0x0010, 0x0200, 2, 3))) {
    std::cerr << "rcif_top kv translate smoke failed\n";
    return 1;
  }

  if (!send_command(
          top,
          0x7103,
          kOpcodeKvMap,
          0,
          pack_kv_entry(0x0010, 0x0300, 4, 5),
          kStatusOk,
          pack_kv_entry(0x0010, 0x0300, 4, 5))) {
    std::cerr << "rcif_top kv remap smoke failed\n";
    return 1;
  }

  for (uint16_t index = 0; index < 7; ++index) {
    const uint16_t virt = 0x0011 + index;
    const uint16_t phys = 0x0400 + index;
    if (!send_command(
            top,
            0x7200 + index,
            kOpcodeKvMap,
            0,
            pack_kv_entry(virt, phys, 1, 1),
            kStatusOk,
            pack_kv_entry(virt, phys, 1, 1))) {
      std::cerr << "rcif_top kv fill smoke failed at index " << index << "\n";
      return 1;
    }
  }

  if (!send_command(
          top,
          0x7300,
          kOpcodeKvMap,
          0,
          pack_kv_entry(0x0018, 0x0500, 1, 1),
          kStatusKvFull,
          pack_kv_entry(0x0018, 0x0500, 1, 1))) {
    std::cerr << "rcif_top kv full smoke failed\n";
    return 1;
  }

  if (!send_command(
          top,
          0x7301,
          kOpcodeKvMap,
          0,
          pack_kv_entry(0x0019, 0x0501, 1, 1) | (1ULL << 40),
          kStatusKvReservedBits,
          pack_kv_entry(0x0019, 0x0501, 1, 1) | (1ULL << 40))) {
    std::cerr << "rcif_top kv reserved bits smoke failed\n";
    return 1;
  }

  if (!send_command(
          top,
          0x7400,
          kOpcodeDmaCopy,
          0,
          pack_dma_desc(0x0020, 0x0030, 0x0004),
          kStatusOk,
          dma_copy_checksum(0x0020, 0x0004))) {
    std::cerr << "rcif_top dma copy smoke failed\n";
    return 1;
  }

  if (!send_command(
          top,
          0x7403,
          kOpcodeDmaCopy,
          0,
          pack_dma_desc(0x0030, 0x0040, 0x0004),
          kStatusOk,
          dma_copy_checksum(0x0020, 0x0004))) {
    std::cerr << "rcif_top dma chained copy smoke failed\n";
    return 1;
  }

  if (!send_command(
          top,
          0x7401,
          kOpcodeDmaCopy,
          0,
          pack_dma_desc(0x0020, 0x0030, 0),
          kStatusDmaZeroLength,
          pack_dma_desc(0x0020, 0x0030, 0))) {
    std::cerr << "rcif_top dma zero length smoke failed\n";
    return 1;
  }

  if (!send_command(
          top,
          0x7402,
          kOpcodeDmaCopy,
          0,
          pack_dma_desc(0x0020, 0x0030, 0x0040) | (1ULL << 48),
          kStatusDmaReservedBits,
          pack_dma_desc(0x0020, 0x0030, 0x0040) | (1ULL << 48))) {
    std::cerr << "rcif_top dma reserved bits smoke failed\n";
    return 1;
  }

  if (!send_command(
          top,
          0x7404,
          kOpcodeDmaCopy,
          0,
          pack_dma_desc(0x00f0, 0x0001, 0x0020),
          kStatusDmaRange,
          0)) {
    std::cerr << "rcif_top dma range smoke failed\n";
    return 1;
  }

  if (!send_get_counter(top, 0x7000, kCounterAccepted, kStatusOk, 27)) {
    std::cerr << "rcif_top accepted counter smoke failed\n";
    return 1;
  }

  if (!send_get_counter(top, 0x7001, kCounterCompleted, kStatusOk, 28)) {
    std::cerr << "rcif_top completed counter smoke failed\n";
    return 1;
  }

  if (!send_get_counter(top, 0x7002, kCounterErrors, kStatusOk, 8)) {
    std::cerr << "rcif_top error counter smoke failed\n";
    return 1;
  }

  if (!send_get_counter(top, 0x7003, 0xff, kStatusUnsupportedCounter, 0xff)) {
    std::cerr << "rcif_top unsupported counter smoke failed\n";
    return 1;
  }

  std::cout << "rcif_top smoke passed\n";
  return 0;
}
