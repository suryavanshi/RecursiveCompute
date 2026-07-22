#include <array>
#include <cstdint>
#include <iostream>
#include <vector>

#include "Vrcif_token_scheduler.h"
#include "verilated.h"

namespace {

constexpr uint32_t kStatusOk = 0;
constexpr uint32_t kStatusGraphDeadlock = 14;
constexpr uint8_t kOpDma = 1;
constexpr uint8_t kOpAttention = 2;
constexpr uint8_t kOpTensor = 3;
constexpr uint8_t kOpComplete = 15;
constexpr uint8_t kTensorUsePrevious = 8;

struct Descriptor {
  uint8_t opcode;
  uint8_t flags;
  uint8_t node_id;
  uint8_t dependencies;
  uint64_t operand0;
  uint32_t operand1;
};

struct Completion {
  uint32_t request_id;
  uint32_t status;
  uint64_t result;
};

void tick(Vrcif_token_scheduler& dut) {
  dut.clk_i = 0;
  dut.eval();
  dut.clk_i = 1;
  dut.eval();
}

void defaults(Vrcif_token_scheduler& dut) {
  dut.graph_write_valid_i = 0;
  dut.req_valid_i = 0;
  dut.query_write_valid_i = 0;
  dut.page_write_valid_i = 0;
  dut.kv_write_valid_i = 0;
  dut.weight_write_valid_i = 0;
  dut.cpl_ready_i = 1;
  dut.trace_clear_i = 0;
  dut.trace_read_index_i = 0;
}

void reset(Vrcif_token_scheduler& dut) {
  defaults(dut);
  dut.rst_ni = 0;
  tick(dut);
  tick(dut);
  dut.rst_ni = 1;
  tick(dut);
}

std::array<uint32_t, 4> pack_descriptor(const Descriptor& desc) {
  unsigned __int128 value = 0;
  value |= static_cast<unsigned __int128>(desc.opcode & 0xf);
  value |= static_cast<unsigned __int128>(desc.flags & 0xf) << 4;
  value |= static_cast<unsigned __int128>(desc.node_id & 0xf) << 8;
  value |= static_cast<unsigned __int128>(desc.dependencies) << 12;
  value |= static_cast<unsigned __int128>(desc.operand0) << 20;
  value |= static_cast<unsigned __int128>(desc.operand1) << 84;
  return {static_cast<uint32_t>(value), static_cast<uint32_t>(value >> 32),
          static_cast<uint32_t>(value >> 64), static_cast<uint32_t>(value >> 96)};
}

void write_descriptor(Vrcif_token_scheduler& dut, uint8_t index, const Descriptor& desc) {
  const auto words = pack_descriptor(desc);
  dut.graph_write_valid_i = 1;
  dut.graph_write_index_i = index;
  for (int word = 0; word < 4; ++word) dut.graph_write_descriptor_i[word] = words[word];
  tick(dut);
  dut.graph_write_valid_i = 0;
}

uint32_t pack_bytes(int8_t a, int8_t b, int8_t c, int8_t d) {
  return static_cast<uint8_t>(a) |
         (static_cast<uint32_t>(static_cast<uint8_t>(b)) << 8) |
         (static_cast<uint32_t>(static_cast<uint8_t>(c)) << 16) |
         (static_cast<uint32_t>(static_cast<uint8_t>(d)) << 24);
}

void program_engines(Vrcif_token_scheduler& dut) {
  dut.query_write_valid_i = 1;
  dut.query_write_head_i = 0;
  dut.query_write_data_i = pack_bytes(1, 0, 0, 0);
  tick(dut);
  dut.query_write_valid_i = 0;

  dut.page_write_valid_i = 1;
  dut.page_write_slot_i = 0;
  dut.page_write_phys_i = 3;
  tick(dut);
  dut.page_write_valid_i = 0;

  dut.kv_write_valid_i = 1;
  dut.kv_write_phys_page_i = 3;
  dut.kv_write_offset_i = 0;
  dut.kv_write_head_i = 0;
  dut.kv_write_key_i = pack_bytes(1, 0, 0, 0);
  dut.kv_write_value_i = pack_bytes(1, 2, 3, 4);
  tick(dut);
  dut.kv_write_valid_i = 0;

  for (uint8_t row = 0; row < 4; ++row) {
    dut.weight_write_valid_i = 1;
    dut.weight_write_row_i = row;
    dut.weight_write_format_i = 0;
    dut.weight_write_data_i = 1u << (8 * row);
    dut.weight_write_zero_point_i = 0;
    dut.weight_write_scale_q8_8_i = 256;
    dut.weight_write_bias_i = 0;
    dut.weight_write_norm_gain_q8_8_i = 256;
    tick(dut);
  }
  dut.weight_write_valid_i = 0;
}

uint64_t pack_dma(uint16_t source, uint16_t destination, uint16_t length) {
  return source | (static_cast<uint64_t>(destination) << 16) |
         (static_cast<uint64_t>(length) << 32);
}

uint64_t pack_attention(uint8_t context_tokens) {
  return (1ULL << 3) | (1ULL << 7) |
         (static_cast<uint64_t>(context_tokens) << 10);
}

void program_transformer_graph(Vrcif_token_scheduler& dut, uint8_t base, bool two_layers) {
  // Deliberately store node 2 first so the scoreboard must skip it until node 1 completes.
  write_descriptor(dut, base + 0, {kOpTensor, kTensorUsePrevious, 2, 1u << 1, 0, 0});
  write_descriptor(dut, base + 1, {kOpDma, 0, 0, 0, pack_dma(1, 10, 1), 0});
  write_descriptor(dut, base + 2, {kOpAttention, 0, 1, 1u << 0, pack_attention(1), 0});
  if (two_layers) {
    write_descriptor(dut, base + 3, {kOpAttention, 0, 3, 1u << 2, pack_attention(1), 0});
    write_descriptor(dut, base + 4, {kOpTensor, kTensorUsePrevious, 4, 1u << 3, 0, 0});
    write_descriptor(dut, base + 5, {kOpComplete, 0, 5, 1u << 4, 0x55, 0});
  } else {
    write_descriptor(dut, base + 3, {kOpComplete, 0, 3, 1u << 2, 0x55, 0});
  }
}

void program_max_service_graph(Vrcif_token_scheduler& dut, uint8_t base) {
  for (uint8_t node = 0; node < 7; ++node) {
    const uint8_t dependencies = node == 0 ? 0 : static_cast<uint8_t>(1u << (node - 1));
    write_descriptor(dut, base + node,
                     {kOpDma, 0, node, dependencies, pack_dma(0, 0, 256), 0});
  }
  write_descriptor(dut, base + 7,
                   {kOpComplete, 0, 7, 1u << 6, 0xabc, 0});
}

bool submit(Vrcif_token_scheduler& dut, uint32_t request_id, uint8_t base,
            uint8_t nodes, uint8_t priority) {
  dut.req_request_id_i = request_id;
  dut.req_graph_base_i = base;
  dut.req_graph_nodes_i = nodes;
  dut.req_priority_i = priority;
  dut.req_valid_i = 1;
  dut.eval();
  if (!dut.req_ready_o) {
    std::cerr << "request queue unexpectedly full\n";
    dut.req_valid_i = 0;
    return false;
  }
  tick(dut);
  dut.req_valid_i = 0;
  return true;
}

bool wait_completion(Vrcif_token_scheduler& dut, Completion& completion, int limit = 512) {
  for (int cycle = 0; cycle < limit; ++cycle) {
    dut.eval();
    if (dut.cpl_valid_o) {
      completion = {dut.cpl_request_id_o, dut.cpl_status_o, dut.cpl_result_o};
      tick(dut);
      return true;
    }
    tick(dut);
  }
  return false;
}

std::vector<std::array<uint32_t, 4>> read_trace(Vrcif_token_scheduler& dut) {
  std::vector<std::array<uint32_t, 4>> trace;
  const uint32_t count = dut.trace_event_count_o;
  for (uint32_t index = 0; index < count; ++index) {
    dut.trace_read_index_i = index;
    dut.eval();
    trace.push_back({dut.trace_read_event_o[0], dut.trace_read_event_o[1],
                     dut.trace_read_event_o[2], dut.trace_read_event_o[3]});
  }
  return trace;
}

void clear_trace(Vrcif_token_scheduler& dut) {
  dut.trace_clear_i = 1;
  tick(dut);
  dut.trace_clear_i = 0;
}

bool check_end_to_end_and_replay(Vrcif_token_scheduler& dut) {
  program_transformer_graph(dut, 0, false);
  clear_trace(dut);
  if (!submit(dut, 0x100, 0, 4, 1)) return false;
  Completion first{};
  if (!wait_completion(dut, first) || first.status != kStatusOk || first.result == 0) {
    std::cerr << "one-block graph failed\n";
    return false;
  }
  const auto first_trace = read_trace(dut);
  if (first_trace.size() != 8) {
    std::cerr << "expected issue/complete trace pair for four nodes, got "
              << first_trace.size() << " events\n";
    return false;
  }

  clear_trace(dut);
  if (!submit(dut, 0x100, 0, 4, 1)) return false;
  Completion replay{};
  if (!wait_completion(dut, replay) || replay.status != first.status ||
      replay.result != first.result || read_trace(dut) != first_trace) {
    std::cerr << "deterministic replay mismatch\n";
    return false;
  }
  return true;
}

bool check_multilayer_and_qos(Vrcif_token_scheduler& dut) {
  program_transformer_graph(dut, 8, true);
  if (!submit(dut, 0x200, 8, 6, 0)) return false;
  tick(dut);  // Let the first request become active.
  if (!submit(dut, 0x201, 8, 6, 0)) return false;
  if (!submit(dut, 0x202, 8, 6, 3)) return false;

  Completion first{}, second{}, third{};
  if (!wait_completion(dut, first) || !wait_completion(dut, second) ||
      !wait_completion(dut, third)) {
    std::cerr << "multi-layer QoS graph timed out\n";
    return false;
  }
  if (first.request_id != 0x200 || second.request_id != 0x202 ||
      third.request_id != 0x201 || first.status != kStatusOk ||
      second.status != kStatusOk || third.status != kStatusOk) {
    std::cerr << "QoS completion order or status mismatch: " << std::hex
              << first.request_id << ", " << second.request_id << ", "
              << third.request_id << "\n";
    return false;
  }
  return true;
}

bool check_deadlock_detection(Vrcif_token_scheduler& dut) {
  write_descriptor(dut, 20, {kOpComplete, 0, 0, 1u << 0, 0, 0});
  if (!submit(dut, 0x300, 20, 1, 1)) return false;
  Completion completion{};
  return wait_completion(dut, completion) && completion.request_id == 0x300 &&
         completion.status == kStatusGraphDeadlock;
}

bool check_qos_cycle_bound(Vrcif_token_scheduler& dut) {
  constexpr uint32_t kActiveLow = 0x400;
  constexpr uint32_t kQueuedLow = 0x401;
  constexpr uint32_t kHigh = 0x402;
  program_max_service_graph(dut, 24);
  write_descriptor(dut, 16, {kOpComplete, 0, 0, 0, 0xabc, 0});
  clear_trace(dut);

  if (!submit(dut, kActiveLow, 24, 8, 0)) return false;
  tick(dut);  // Move the first maximum-service graph into execution.
  if (!submit(dut, kQueuedLow, 24, 8, 0)) return false;
  if (!submit(dut, kHigh, 16, 1, 3)) return false;

  const uint32_t advertised_bound = dut.qos_bound_cycles_o;
  std::vector<uint32_t> completion_order;
  uint32_t high_external_latency = 0;
  bool saw_high = false;
  for (uint32_t cycle = 1; cycle <= advertised_bound; ++cycle) {
    dut.eval();
    if (dut.cpl_valid_o) {
      const uint32_t request_id = dut.cpl_request_id_o;
      if (dut.cpl_status_o != kStatusOk) {
        std::cerr << "bounded QoS graph returned an error\n";
        return false;
      }
      completion_order.push_back(request_id);
      if (request_id == kHigh) {
        high_external_latency = cycle;
        saw_high = true;
        if (dut.qos_last_request_id_o != kHigh ||
            dut.qos_last_latency_o > advertised_bound ||
            dut.qos_bound_violation_o) {
          std::cerr << "internal QoS retirement bound mismatch\n";
          return false;
        }
      }
    }
    tick(dut);
    if (saw_high && completion_order.size() >= 2) break;
  }

  if (!saw_high || high_external_latency > advertised_bound ||
      completion_order.size() < 2 || completion_order[0] != kActiveLow ||
      completion_order[1] != kHigh) {
    std::cerr << "high-priority request missed its " << advertised_bound
              << " cycle bound or was bypassed\n";
    return false;
  }

  std::cout << "qos latency bound: observed " << high_external_latency
            << " cycles <= " << advertised_bound << " cycles\n";

  Completion queued_low{};
  if (!wait_completion(dut, queued_low, 8192) || queued_low.request_id != kQueuedLow ||
      queued_low.status != kStatusOk || dut.qos_bound_violation_o) {
    std::cerr << "queued low-priority graph failed after bounded request\n";
    return false;
  }
  return true;
}

bool check_full_queue_priority_bound(Vrcif_token_scheduler& dut) {
  constexpr uint32_t kFirst = 0x500;
  constexpr uint32_t kSubject = 0x504;
  if (!submit(dut, kFirst, 24, 8, 3)) return false;
  tick(dut);
  for (uint32_t request_id = kFirst + 1; request_id <= kSubject; ++request_id) {
    if (!submit(dut, request_id, 24, 8, 3)) return false;
  }

  const uint32_t advertised_bound = dut.qos_bound_cycles_o;
  std::vector<uint32_t> completion_order;
  uint32_t subject_latency = 0;
  for (uint32_t cycle = 1; cycle <= advertised_bound; ++cycle) {
    dut.eval();
    if (dut.cpl_valid_o) {
      completion_order.push_back(dut.cpl_request_id_o);
      if (dut.cpl_request_id_o == kSubject) subject_latency = cycle;
    }
    tick(dut);
    if (subject_latency != 0) break;
  }

  if (completion_order.size() != 5 || subject_latency == 0 ||
      dut.qos_last_request_id_o != kSubject ||
      dut.qos_last_latency_o > advertised_bound || dut.qos_bound_violation_o) {
    std::cerr << "full maximum-priority queue missed its latency bound\n";
    return false;
  }
  for (uint32_t index = 0; index < completion_order.size(); ++index) {
    if (completion_order[index] != kFirst + index) {
      std::cerr << "equal-priority age ordering mismatch\n";
      return false;
    }
  }
  std::cout << "full-queue qos bound: observed " << subject_latency
            << " cycles <= " << advertised_bound << " cycles\n";
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vrcif_token_scheduler dut;
  reset(dut);
  program_engines(dut);

  if (!check_end_to_end_and_replay(dut)) return 1;
  if (!check_multilayer_and_qos(dut)) return 1;
  if (!check_qos_cycle_bound(dut)) return 1;
  if (!check_full_queue_priority_bound(dut)) return 1;
  if (!check_deadlock_detection(dut)) {
    std::cerr << "dependency deadlock detection failed\n";
    return 1;
  }

  std::cout << "rcif_token_scheduler: PASS\n";
  return 0;
}
