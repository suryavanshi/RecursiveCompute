#include <array>
#include <cstdint>
#include <iostream>

#include "Vrcif_top.h"
#include "verilated.h"
#if VM_COVERAGE
#include "verilated_cov.h"
#endif

namespace {

constexpr uint16_t kNop = 0x0000;
constexpr uint16_t kEcho = 0x0001;
constexpr uint16_t kAttnQkDot = 0x0040;
constexpr uint32_t kOk = 0;
constexpr uint32_t kUnsupportedOpcode = 1;
constexpr uint32_t kUnsupportedFlags = 2;

uint64_t rng_state = 0x9e3779b97f4a7c15ULL;

uint64_t random_u64() {
  rng_state ^= rng_state << 7;
  rng_state ^= rng_state >> 9;
  rng_state ^= rng_state << 8;
  return rng_state;
}

void tick(Vrcif_top& top) {
  top.clk_i = 0;
  top.eval();
  top.clk_i = 1;
  top.eval();
}

void reset(Vrcif_top& top, int cycles) {
  top.rst_ni = 0;
  top.cmd_valid_i = 0;
  top.cpl_ready_i = 0;
  for (int cycle = 0; cycle < cycles; ++cycle) {
    tick(top);
  }
  top.rst_ni = 1;
  top.cpl_ready_i = 1;
  tick(top);
  if (top.cpl_valid_o) {
    std::cerr << "completion leaked across reset\n";
    std::exit(1);
  }
}

int32_t qk_dot(uint64_t payload) {
  int32_t total = 0;
  for (int lane = 0; lane < 4; ++lane) {
    const int8_t query = static_cast<int8_t>(payload >> (8 * lane));
    const int8_t key = static_cast<int8_t>(payload >> (32 + 8 * lane));
    total += static_cast<int32_t>(query) * static_cast<int32_t>(key);
  }
  return total;
}

bool transact(Vrcif_top& top, uint32_t id, uint16_t opcode, uint16_t flags,
              uint64_t payload, uint32_t expected_status,
              uint64_t expected_result, int stall_cycles) {
  top.cmd_valid_i = 1;
  top.cmd_request_id_i = id;
  top.cmd_opcode_i = opcode;
  top.cmd_flags_i = flags;
  top.cmd_payload_i = payload;
  for (int cycle = 0; cycle < 64; ++cycle) {
    top.eval();
    if (top.cmd_ready_o) {
      tick(top);
      top.cmd_valid_i = 0;
      break;
    }
    tick(top);
    if (cycle == 63) {
      std::cerr << "command admission timeout\n";
      return false;
    }
  }

  top.cpl_ready_i = 0;
  bool captured = false;
  uint32_t held_id = 0;
  uint32_t held_status = 0;
  uint64_t held_result = 0;
  for (int cycle = 0; cycle < stall_cycles; ++cycle) {
    top.eval();
    if (top.cpl_valid_o) {
      if (!captured) {
        captured = true;
        held_id = top.cpl_request_id_o;
        held_status = top.cpl_status_o;
        held_result = top.cpl_result_o;
      } else if (top.cpl_request_id_o != held_id ||
                 top.cpl_status_o != held_status ||
                 top.cpl_result_o != held_result) {
        std::cerr << "completion changed under randomized backpressure\n";
        return false;
      }
    }
    tick(top);
  }

  top.cpl_ready_i = 1;
  for (int cycle = 0; cycle < 128; ++cycle) {
    top.eval();
    if (top.cpl_valid_o) {
      const bool matches = top.cpl_request_id_o == id &&
                           top.cpl_status_o == expected_status &&
                           top.cpl_result_o == expected_result;
      tick(top);
      return matches;
    }
    tick(top);
  }
  std::cerr << "completion timeout for request " << id << "\n";
  return false;
}

}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vrcif_top top;
  reset(top, 1);

  std::array<unsigned, 4> opcode_bins{};
  unsigned backpressure_bin = 0;
  unsigned reset_bin = 1;

  for (uint32_t index = 0; index < 1024; ++index) {
    if (index != 0 && index % 127 == 0) {
      reset(top, 1 + static_cast<int>(random_u64() % 4));
      ++reset_bin;
    }

    const uint64_t payload = random_u64();
    const uint16_t flags = (random_u64() % 11 == 0) ? 1 : 0;
    const unsigned choice = static_cast<unsigned>(random_u64() % 4);
    uint16_t opcode = 0;
    uint32_t status = flags ? kUnsupportedFlags : kOk;
    uint64_t result = 0;

    if (choice == 0) {
      opcode = kNop;
    } else if (choice == 1) {
      opcode = kEcho;
      result = payload;
    } else if (choice == 2) {
      opcode = kAttnQkDot;
      result = flags ? 0 :
          static_cast<uint64_t>(static_cast<int64_t>(qk_dot(payload)));
    } else {
      opcode = static_cast<uint16_t>(0x8000 | (random_u64() & 0x7fff));
      status = flags ? kUnsupportedFlags : kUnsupportedOpcode;
      result = opcode;
    }

    const int stall = static_cast<int>(random_u64() % 13);
    backpressure_bin += stall != 0;
    ++opcode_bins[choice];
    if (!transact(top, 0x90000000U + index, opcode, flags, payload,
                  status, result, stall)) {
      std::cerr << "random full-chip transaction failed at index " << index << "\n";
      return 1;
    }
  }

  for (unsigned count : opcode_bins) {
    if (count < 200) {
      std::cerr << "opcode coverage bin below target\n";
      return 1;
    }
  }
  if (backpressure_bin < 800 || reset_bin < 8) {
    std::cerr << "backpressure/reset coverage bins below target\n";
    return 1;
  }

  #if VM_COVERAGE
  if (argc > 1) {
    VerilatedCov::write(argv[1]);
  }
  #endif
  std::cout << "phase9 randomized full-chip test passed: 1024 commands, "
            << backpressure_bin << " stalled completions, " << reset_bin
            << " reset sequences\n";
  return 0;
}
