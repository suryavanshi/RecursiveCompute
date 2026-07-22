#include <array>
#include <cstdint>
#include <iostream>
#include <vector>

#include "Vrcif_attn_engine.h"
#include "verilated.h"

namespace {
using Vec = std::array<int8_t, 4>;

uint32_t pack(const Vec& vector) {
  uint32_t bits = 0;
  for (int dim = 0; dim < 4; ++dim) {
    bits |= static_cast<uint32_t>(static_cast<uint8_t>(vector[dim])) << (8 * dim);
  }
  return bits;
}

std::array<int16_t, 4> unpack_context(uint64_t bits) {
  std::array<int16_t, 4> result{};
  for (int dim = 0; dim < 4; ++dim) {
    result[dim] = static_cast<int16_t>((bits >> (16 * dim)) & 0xffff);
  }
  return result;
}

int dot(const Vec& query, const Vec& key) {
  int score = 0;
  for (int dim = 0; dim < 4; ++dim) score += query[dim] * key[dim];
  return score;
}

std::array<int16_t, 4> reference(
    const Vec& query,
    const std::vector<Vec>& keys,
    const std::vector<Vec>& values,
    uint32_t keep_mask) {
  constexpr int64_t one = 1 << 15;
  bool have = false;
  int maximum = 0;
  int64_t denominator = 0;
  std::array<int64_t, 4> accumulator{};
  for (size_t token = 0; token < keys.size(); ++token) {
    if (((keep_mask >> token) & 1U) == 0) continue;
    const int score = dot(query, keys[token]);
    if (!have) {
      have = true;
      maximum = score;
      denominator = one;
      for (int dim = 0; dim < 4; ++dim) accumulator[dim] = values[token][dim] * one;
    } else if (score > maximum) {
      const int shift = std::min(score - maximum, 15);
      const int64_t weight = one >> shift;
      denominator = ((denominator * weight) >> 15) + one;
      for (int dim = 0; dim < 4; ++dim) {
        accumulator[dim] = ((accumulator[dim] * weight) >> 15) + values[token][dim] * one;
      }
      maximum = score;
    } else {
      const int shift = std::min(maximum - score, 15);
      const int64_t weight = one >> shift;
      denominator += weight;
      for (int dim = 0; dim < 4; ++dim) accumulator[dim] += values[token][dim] * weight;
    }
  }
  std::array<int16_t, 4> result{};
  if (have) {
    for (int dim = 0; dim < 4; ++dim) result[dim] = accumulator[dim] / denominator;
  }
  return result;
}

void tick(Vrcif_attn_engine& top) {
  top.clk_i = 0;
  top.eval();
  top.clk_i = 1;
  top.eval();
}

void reset(Vrcif_attn_engine& top) {
  top.rst_ni = 0;
  top.query_write_valid_i = 0;
  top.page_write_valid_i = 0;
  top.kv_write_valid_i = 0;
  top.req_valid_i = 0;
  top.rsp_ready_i = 1;
  tick(top);
  tick(top);
  top.rst_ni = 1;
  tick(top);
}

void write_query(Vrcif_attn_engine& top, int head, const Vec& query) {
  top.query_write_valid_i = 1;
  top.query_write_head_i = head;
  top.query_write_data_i = pack(query);
  tick(top);
  top.query_write_valid_i = 0;
}

void map_page(Vrcif_attn_engine& top, int slot, int physical) {
  top.page_write_valid_i = 1;
  top.page_write_slot_i = slot;
  top.page_write_phys_i = physical;
  tick(top);
  top.page_write_valid_i = 0;
}

void write_kv(Vrcif_attn_engine& top, int physical, int offset, int head, const Vec& key, const Vec& value) {
  top.kv_write_valid_i = 1;
  top.kv_write_phys_page_i = physical;
  top.kv_write_offset_i = offset;
  top.kv_write_head_i = head;
  top.kv_write_key_i = pack(key);
  top.kv_write_value_i = pack(value);
  tick(top);
  top.kv_write_valid_i = 0;
}

bool run_attention(
    Vrcif_attn_engine& top,
    int query_head,
    int num_query_heads,
    int num_kv_heads,
    int context,
    int window_start,
    int sinks,
    bool explicit_enable,
    uint32_t explicit_mask,
    const std::array<int16_t, 4>& expected,
    bool expected_empty,
    bool exercise_backpressure = false) {
  top.eval();
  if (!top.req_ready_o) return false;
  top.req_query_head_i = query_head;
  top.req_num_query_heads_i = num_query_heads;
  top.req_num_kv_heads_i = num_kv_heads;
  top.req_context_tokens_i = context;
  top.req_window_start_i = window_start;
  top.req_sink_tokens_i = sinks;
  top.req_explicit_mask_enable_i = explicit_enable;
  top.req_explicit_mask_i = explicit_mask;
  top.req_valid_i = 1;
  tick(top);
  top.req_valid_i = 0;

  // The page reader, QK tile, and softmax accept one kept token per cycle after
  // pipeline fill; the fixed bound includes start/drain/reduction latency.
  const int latency_bound = context + 12;
  for (int cycle = 0; cycle < latency_bound; ++cycle) {
    top.eval();
    if (top.rsp_valid_o) {
      if (exercise_backpressure) {
        const uint64_t held_context = top.rsp_context_o;
        top.rsp_ready_i = 0;
        for (int stall = 0; stall < 4; ++stall) {
          tick(top);
          if (!top.rsp_valid_o || top.rsp_context_o != held_context) return false;
        }
        top.rsp_ready_i = 1;
      }
      const auto actual = unpack_context(top.rsp_context_o);
      if (actual != expected || static_cast<bool>(top.rsp_all_masked_o) != expected_empty) {
        std::cerr << "attention mismatch actual=";
        for (auto item : actual) std::cerr << item << " ";
        std::cerr << "expected=";
        for (auto item : expected) std::cerr << item << " ";
        std::cerr << "empty=" << static_cast<int>(top.rsp_all_masked_o) << "\n";
        return false;
      }
      tick(top);
      return true;
    }
    tick(top);
  }
  std::cerr << "attention response timeout\n";
  return false;
}
}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vrcif_attn_engine top;
  reset(top);

  const Vec query{1, 0, 0, 0};
  for (int head = 0; head < 4; ++head) write_query(top, head, query);

  // Logical pages 0 and 1 deliberately map to physical pages 2 and 0.
  map_page(top, 0, 2);
  map_page(top, 1, 0);
  std::vector<Vec> head0_keys, head0_values, head1_keys, head1_values;
  for (int token = 0; token < 6; ++token) {
    const int physical = token < 4 ? 2 : 0;
    const int offset = token % 4;
    Vec key0{static_cast<int8_t>(token), 0, 0, 0};
    Vec value0{static_cast<int8_t>(10 + token * 5), static_cast<int8_t>(token), -2, 3};
    Vec key1{static_cast<int8_t>(token * 2), 0, 0, 0};
    Vec value1{static_cast<int8_t>(60 + token * 4), static_cast<int8_t>(20 - token), 7, -8};
    write_kv(top, physical, offset, 0, key0, value0);
    write_kv(top, physical, offset, 1, key1, value1);
    head0_keys.push_back(key0);
    head0_values.push_back(value0);
    head1_keys.push_back(key1);
    head1_values.push_back(value1);
  }

  const uint32_t all_six = 0x3f;
  if (!run_attention(top, 3, 4, 2, 6, 0, 0, true, all_six,
                     reference(query, head1_keys, head1_values, all_six), false, true)) {
    std::cerr << "GQA/non-contiguous/backpressure test failed\n";
    return 1;
  }

  // Sliding window keeps tokens >=4, sink keeps token 0, explicit mask removes token 4.
  const uint32_t masked_keep = (1U << 0) | (1U << 5);
  if (!run_attention(top, 2, 4, 1, 6, 4, 1, true, ~(1U << 4),
                     reference(query, head0_keys, head0_values, masked_keep), false)) {
    std::cerr << "MQA/mask/window/sink test failed\n";
    return 1;
  }

  const std::array<int16_t, 4> zero{};
  if (!run_attention(top, 0, 4, 2, 6, 6, 0, true, 0, zero, true)) {
    std::cerr << "all-masked test failed\n";
    return 1;
  }

  std::cout << "rcif_attn_engine directed tests passed\n";
  return 0;
}
