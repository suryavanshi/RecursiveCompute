#include "Vrcif_collective_cluster.h"
#include "verilated.h"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <iostream>

namespace {
constexpr int kNodes = 4;

void tick(Vrcif_collective_cluster& dut) {
  dut.clk_i = 0;
  dut.eval();
  dut.clk_i = 1;
  dut.eval();
}

[[noreturn]] void fail(const char* message) {
  std::cerr << "distributed-cluster test failure: " << message << '\n';
  std::exit(1);
}

void set_values(Vrcif_collective_cluster& dut,
                const std::array<uint32_t, kNodes>& values) {
  for (int node = 0; node < kNodes; ++node) dut.cmd_local_values_i[node] = values[node];
}

void check_credits(const Vrcif_collective_cluster& dut) {
  for (int link = 0; link < kNodes; ++link) {
    const int credits = (dut.credits_o >> (2 * link)) & 0x3;
    if (credits < 0 || credits > 2) fail("credit count escaped its bound");
  }
}

void run_collective(Vrcif_collective_cluster& dut,
                    const std::array<uint32_t, kNodes>& values,
                    uint8_t collective_id, uint32_t expected) {
  for (int cycle = 0; cycle < 32 && !dut.cmd_ready_o; ++cycle) tick(dut);
  if (!dut.cmd_ready_o) {
    std::cerr << "cluster state: done=" << int(dut.done_o)
              << " error=" << int(dut.protocol_error_o)
              << " credits=0x" << std::hex << int(dut.credits_o) << std::dec << '\n';
    fail("cluster did not quiesce");
  }
  set_values(dut, values);
  dut.cmd_collective_id_i = collective_id;
  dut.cmd_valid_i = 1;
  tick(dut);
  dut.cmd_valid_i = 0;

  for (int cycle = 0; cycle < 256 && !dut.done_o; ++cycle) {
    // Exercise independent receiver backpressure while guaranteeing fairness:
    // no link is stalled for more than one of every five cycles.
    dut.link_stall_i = (cycle % 5 == 1) ? (1u << ((cycle / 5) % kNodes)) : 0;
    tick(dut);
    check_credits(dut);
    if (dut.protocol_error_o) fail("node reported a protocol error");
  }
  dut.link_stall_i = 0;
  if (!dut.done_o) {
    std::cerr << "timeout state: ready=" << int(dut.cmd_ready_o)
              << " error=" << int(dut.protocol_error_o)
              << " credits=0x" << std::hex << int(dut.credits_o)
              << " results=" << dut.results_o[0] << ',' << dut.results_o[1]
              << ',' << dut.results_o[2] << ',' << dut.results_o[3]
              << std::dec << '\n';
    fail("distributed AllReduce timed out");
  }
  for (int node = 0; node < kNodes; ++node)
    if (dut.results_o[node] != expected) fail("distributed reduction mismatch");
}
}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vrcif_collective_cluster dut;
  dut.rst_ni = 0;
  dut.cmd_valid_i = 0;
  dut.link_stall_i = 0;
  tick(dut);
  tick(dut);
  dut.rst_ni = 1;
  tick(dut);

  run_collective(dut, {1, 2, 3, 4}, 0x31, 10);
  run_collective(dut, {10, 20, 30, 40}, 0x32, 100);

  std::cout << "distributed four-chip collective tests passed\n";
  return 0;
}
