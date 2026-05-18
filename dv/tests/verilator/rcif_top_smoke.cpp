#include <cstdint>
#include <iostream>

#include "Vrcif_top.h"
#include "verilated.h"

namespace {

constexpr uint16_t kOpcodeNop = 0x0000;
constexpr uint16_t kOpcodeEcho = 0x0001;
constexpr uint32_t kStatusOk = 0;
constexpr uint32_t kStatusUnsupportedOpcode = 1;
constexpr uint32_t kStatusUnsupportedFlags = 2;

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

  std::cout << "rcif_top smoke passed\n";
  return 0;
}
