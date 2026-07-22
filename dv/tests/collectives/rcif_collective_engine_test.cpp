#include "Vrcif_collective_engine.h"
#include "verilated.h"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <iostream>

namespace {
constexpr int kNodes = 4;
constexpr uint8_t kOk = 0;
constexpr uint8_t kPartition = 3;
constexpr uint8_t kRetryExhausted = 4;

void tick(Vrcif_collective_engine& dut) {
  dut.clk_i = 0;
  dut.eval();
  dut.clk_i = 1;
  dut.eval();
}

[[noreturn]] void fail(const char* message) {
  std::cerr << "collective test failure: " << message << '\n';
  std::exit(1);
}

void clear_inputs(Vrcif_collective_engine& dut) {
  dut.topo_cfg_valid_i = 0;
  dut.route_cfg_valid_i = 0;
  dut.fault_cfg_valid_i = 0;
  dut.fault_cfg_clear_i = 0;
  dut.cmd_valid_i = 0;
  dut.rsp_ready_i = 0;
}

void reset(Vrcif_collective_engine& dut) {
  clear_inputs(dut);
  dut.rst_ni = 0;
  tick(dut);
  tick(dut);
  dut.rst_ni = 1;
  tick(dut);
}

void configure_node(Vrcif_collective_engine& dut, int node, int partition) {
  dut.topo_cfg_valid_i = 1;
  dut.topo_cfg_node_i = node;
  dut.topo_cfg_active_i = 1;
  dut.topo_cfg_partition_i = partition;
  dut.topo_cfg_ring_next_i = (node + 1) % kNodes;
  dut.topo_cfg_tree_parent_i = 0;
  tick(dut);
  dut.topo_cfg_valid_i = 0;
}

void configure_full_mesh(Vrcif_collective_engine& dut) {
  for (int node = 0; node < kNodes; ++node) configure_node(dut, node, 1);
  for (int source = 0; source < kNodes; ++source) {
    for (int destination = 0; destination < kNodes; ++destination) {
      dut.route_cfg_valid_i = 1;
      dut.route_cfg_node_i = source;
      dut.route_cfg_destination_i = destination;
      dut.route_cfg_next_hop_i = destination;
      dut.route_cfg_link_enable_i = 1;
      tick(dut);
    }
  }
  dut.route_cfg_valid_i = 0;
}

void set_local_values(Vrcif_collective_engine& dut,
                      const std::array<uint32_t, kNodes>& values) {
  for (int node = 0; node < kNodes; ++node) dut.cmd_local_values_i[node] = values[node];
}

void set_alltoall_values(Vrcif_collective_engine& dut) {
  for (int source = 0; source < kNodes; ++source)
    for (int destination = 0; destination < kNodes; ++destination)
      dut.cmd_alltoall_values_i[source * kNodes + destination] =
          100 * source + destination;
}

void submit(Vrcif_collective_engine& dut, uint8_t opcode, uint8_t id,
            uint8_t retry_limit = 2) {
  if (!dut.cmd_ready_o) fail("command was not ready");
  dut.cmd_valid_i = 1;
  dut.cmd_opcode_i = opcode;
  dut.cmd_collective_id_i = id;
  dut.cmd_partition_i = 1;
  dut.cmd_participants_i = 0xf;
  dut.cmd_root_i = 0;
  dut.cmd_retry_limit_i = retry_limit;
  tick(dut);
  dut.cmd_valid_i = 0;
}

void wait_response(Vrcif_collective_engine& dut, int limit = 512) {
  for (int cycle = 0; cycle < limit && !dut.rsp_valid_o; ++cycle) tick(dut);
  if (!dut.rsp_valid_o) fail("operation timed out");
}

void accept_response(Vrcif_collective_engine& dut) {
  dut.rsp_ready_i = 1;
  tick(dut);
  dut.rsp_ready_i = 0;
}

void expect_reduction(const Vrcif_collective_engine& dut, uint8_t id,
                      uint32_t value) {
  if (dut.rsp_collective_id_o != id || dut.rsp_status_o != kOk ||
      !dut.rsp_committed_o)
    fail("successful reduction status mismatch");
  for (int node = 0; node < kNodes; ++node)
    if (dut.rsp_local_values_o[node] != value) fail("reduction data mismatch");
}
}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vrcif_collective_engine dut;
  reset(dut);
  configure_full_mesh(dut);
  set_local_values(dut, {1, 2, 3, 4});
  set_alltoall_values(dut);

  submit(dut, 0, 0x11);
  wait_response(dut);
  expect_reduction(dut, 0x11, 10);
  accept_response(dut);

  submit(dut, 1, 0x12);
  wait_response(dut);
  expect_reduction(dut, 0x12, 10);
  accept_response(dut);

  submit(dut, 2, 0x13);
  wait_response(dut);
  if (dut.rsp_status_o != kOk || !dut.rsp_committed_o) fail("AllToAll failed");
  for (int destination = 0; destination < kNodes; ++destination)
    for (int source = 0; source < kNodes; ++source)
      if (dut.rsp_alltoall_values_o[destination * kNodes + source] !=
          static_cast<uint32_t>(100 * source + destination))
        fail("AllToAll transpose mismatch");
  accept_response(dut);

  dut.fault_cfg_valid_i = 1;
  dut.fault_cfg_source_i = 0;
  dut.fault_cfg_destination_i = 1;
  dut.fault_cfg_persistent_i = 0;
  tick(dut);
  dut.fault_cfg_valid_i = 0;
  submit(dut, 0, 0x14, 2);
  wait_response(dut);
  expect_reduction(dut, 0x14, 10);
  if (dut.rsp_retry_count_o != 1) fail("transient retry count mismatch");
  accept_response(dut);

  dut.fault_cfg_valid_i = 1;
  dut.fault_cfg_source_i = 0;
  dut.fault_cfg_destination_i = 1;
  dut.fault_cfg_persistent_i = 1;
  tick(dut);
  dut.fault_cfg_valid_i = 0;
  submit(dut, 0, 0x15, 2);
  wait_response(dut);
  if (dut.rsp_status_o != kRetryExhausted || dut.rsp_committed_o ||
      dut.rsp_retry_count_o != 2 || dut.rsp_fault_source_o != 0 ||
      dut.rsp_fault_destination_o != 1)
    fail("persistent fault containment mismatch");
  for (int word = 0; word < 4; ++word)
    if (dut.rsp_local_values_o[word] != 0) fail("failed operation leaked data");
  accept_response(dut);
  dut.fault_cfg_clear_i = 1;
  tick(dut);
  dut.fault_cfg_clear_i = 0;

  configure_node(dut, 3, 2);
  submit(dut, 0, 0x16);
  wait_response(dut);
  if (dut.rsp_status_o != kPartition || dut.rsp_committed_o)
    fail("partition escape was not contained");
  accept_response(dut);
  configure_node(dut, 3, 1);

  std::cout << "collective engine directed tests passed\n";
  return 0;
}
