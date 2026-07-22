#include <array>
#include <cstdint>
#include <iostream>

#include "Vrcif_tensor_array.h"
#include "verilated.h"

namespace {
using ByteVec = std::array<int8_t, 4>;
using OutVec = std::array<int16_t, 4>;

uint32_t pack_int8(const ByteVec& values) {
  uint32_t result = 0;
  for (int lane = 0; lane < 4; ++lane) {
    result |= static_cast<uint32_t>(static_cast<uint8_t>(values[lane])) << (lane * 8);
  }
  return result;
}

uint32_t pack_int4(const ByteVec& values) {
  uint32_t result = 0;
  for (int lane = 0; lane < 4; ++lane) {
    result |= static_cast<uint32_t>(values[lane] & 0xf) << (lane * 4);
  }
  return result;
}

OutVec unpack(uint64_t bits) {
  OutVec result{};
  for (int lane = 0; lane < 4; ++lane) {
    result[lane] = static_cast<int16_t>((bits >> (lane * 16)) & 0xffff);
  }
  return result;
}

void tick(Vrcif_tensor_array& top) {
  top.clk_i = 0;
  top.eval();
  top.clk_i = 1;
  top.eval();
}

void reset(Vrcif_tensor_array& top) {
  top.rst_ni = 0;
  top.weight_write_valid_i = 0;
  top.req_valid_i = 0;
  top.rsp_ready_i = 1;
  tick(top);
  tick(top);
  top.rst_ni = 1;
  tick(top);
}

bool write_row(
    Vrcif_tensor_array& top,
    int row,
    int format,
    uint32_t weights,
    int zero_point,
    int scale,
    int bias,
    int norm_gain = 256) {
  top.eval();
  if (!top.weight_write_ready_o) return false;
  top.weight_write_valid_i = 1;
  top.weight_write_row_i = row;
  top.weight_write_format_i = format;
  top.weight_write_data_i = weights;
  top.weight_write_zero_point_i = static_cast<uint8_t>(zero_point);
  top.weight_write_scale_q8_8_i = static_cast<uint16_t>(scale);
  top.weight_write_bias_i = static_cast<uint32_t>(bias);
  top.weight_write_norm_gain_q8_8_i = static_cast<uint16_t>(norm_gain);
  tick(top);
  top.weight_write_valid_i = 0;
  return true;
}

bool run(
    Vrcif_tensor_array& top,
    const ByteVec& activation,
    int activation_mode,
    bool norm_enable,
    int epsilon,
    const OutVec& expected,
    uint8_t expected_saturated,
    bool expected_error,
    bool backpressure = false) {
  top.eval();
  if (!top.req_ready_o) return false;
  top.req_valid_i = 1;
  top.req_activation_i = pack_int8(activation);
  top.req_activation_mode_i = activation_mode;
  top.req_norm_enable_i = norm_enable;
  top.req_norm_epsilon_i = epsilon;
  tick(top);
  top.req_valid_i = 0;

  for (int cycle = 0; cycle < 20; ++cycle) {
    top.eval();
    if (top.rsp_valid_o) {
      if (backpressure) {
        const uint64_t held = top.rsp_result_o;
        const uint8_t held_saturation = top.rsp_saturated_o;
        top.rsp_ready_i = 0;
        for (int stall = 0; stall < 5; ++stall) {
          tick(top);
          if (!top.rsp_valid_o || top.rsp_result_o != held ||
              top.rsp_saturated_o != held_saturation) return false;
        }
        top.rsp_ready_i = 1;
      }
      const auto actual = unpack(top.rsp_result_o);
      if (actual != expected || top.rsp_saturated_o != expected_saturated ||
          static_cast<bool>(top.rsp_config_error_o) != expected_error) {
        std::cerr << "tensor mismatch actual=";
        for (auto value : actual) std::cerr << value << " ";
        std::cerr << "saturation=" << static_cast<int>(top.rsp_saturated_o)
                  << " error=" << static_cast<int>(top.rsp_config_error_o) << "\n";
        return false;
      }
      tick(top);
      return true;
    }
    tick(top);
  }
  std::cerr << "tensor response timeout\n";
  return false;
}
}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vrcif_tensor_array top;
  reset(top);

  if (!write_row(top, 0, 0, pack_int8({1, 2, 3, 4}), 0, 256, 1) ||
      !write_row(top, 1, 1, pack_int4({-8, -1, 0, 7}), -1, 128, -2) ||
      !write_row(top, 2, 0, pack_int8({-1, -1, -1, -1}), 0, 384, 10) ||
      !write_row(top, 3, 1, pack_int4({7, 7, 7, 7}), 0, 256, -40)) {
    std::cerr << "weight programming failed\n";
    return 1;
  }
  if (!run(top, {2, -3, 4, 1}, 1, false, 0, {13, 0, 4, 0}, 0, false, true)) {
    std::cerr << "mixed INT8/INT4/ReLU/backpressure test failed\n";
    return 1;
  }

  // Identity rows produce [3,4,0,0], then integer RMSNorm emits Q8.8 values.
  for (int row = 0; row < 4; ++row) {
    ByteVec identity{0, 0, 0, 0};
    identity[row] = 1;
    if (!write_row(top, row, 0, pack_int8(identity), 0, 256, 0, 256)) return 1;
  }
  if (!run(top, {3, 4, 0, 0}, 0, true, 0, {384, 512, 0, 0}, 0, false)) {
    std::cerr << "integer RMSNorm test failed\n";
    return 1;
  }

  const auto maximum_row = pack_int8({127, 127, 127, 127});
  for (int row = 0; row < 4; ++row) {
    if (!write_row(top, row, 0, maximum_row, 0, 32767, 0)) return 1;
  }
  if (!run(top, {127, 127, 127, 127}, 2, false, 0,
           {127, 127, 127, 127}, 0xf, false)) {
    std::cerr << "saturation/clamp test failed\n";
    return 1;
  }

  const auto minimum_row = pack_int8({-128, -128, -128, -128});
  for (int row = 0; row < 4; ++row) {
    if (!write_row(top, row, 0, minimum_row, 0, 32767, 0)) return 1;
  }
  if (!run(top, {127, 127, 127, 127}, 2, false, 0,
           {-128, -128, -128, -128}, 0xf, false)) {
    std::cerr << "negative saturation/clamp test failed\n";
    return 1;
  }

  if (!write_row(top, 0, 3, 0, 0, 256, 0)) return 1;
  if (!run(top, {1, 2, 3, 4}, 0, true, 0, {0, 0, 0, 0}, 0, true)) {
    std::cerr << "invalid-format test failed\n";
    return 1;
  }

  if (!write_row(top, 0, 0, pack_int8({1, 0, 0, 0}), 0, 256, 0)) return 1;
  if (!run(top, {1, 2, 3, 4}, 3, false, 0, {0, 0, 0, 0}, 0, true)) {
    std::cerr << "invalid-activation test failed\n";
    return 1;
  }

  std::cout << "rcif_tensor_array format tests passed\n";
  return 0;
}
