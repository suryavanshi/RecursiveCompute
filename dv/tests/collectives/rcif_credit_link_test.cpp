#include "Vrcif_credit_link.h"
#include "verilated.h"

#include <cstdint>
#include <cstdlib>
#include <iostream>

namespace {
void tick(Vrcif_credit_link& dut) {
  dut.clk_i = 0;
  dut.eval();
  dut.clk_i = 1;
  dut.eval();
}

[[noreturn]] void fail(const char* message) {
  std::cerr << "credit-link test failure: " << message << '\n';
  std::exit(1);
}

void drive_word(Vrcif_credit_link& dut, uint32_t value) {
  dut.tx_flit_i[0] = value;
  dut.tx_flit_i[1] = 0;
  dut.tx_flit_i[2] = 0;
  dut.tx_flit_i[3] = 0;
}
}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vrcif_credit_link dut;
  dut.rst_ni = 0;
  dut.flush_i = 0;
  dut.tx_valid_i = 0;
  dut.rx_ready_i = 0;
  tick(dut);
  dut.rst_ni = 1;
  tick(dut);
  if (dut.credits_o != 4 || dut.rx_valid_o) fail("reset credit count mismatch");

  for (uint32_t value = 1; value <= 4; ++value) {
    if (!dut.tx_ready_o) fail("link filled too early");
    drive_word(dut, value);
    dut.tx_valid_i = 1;
    tick(dut);
  }
  dut.tx_valid_i = 0;
  if (dut.tx_ready_o || dut.credits_o != 0) fail("full link advertised credit");
  if (!dut.rx_valid_o || dut.rx_flit_o[0] != 1) fail("FIFO head mismatch");

  tick(dut);
  if (dut.rx_flit_o[0] != 1) fail("stalled payload was not stable");

  dut.rx_ready_i = 1;
  for (uint32_t expected = 1; expected <= 4; ++expected) {
    if (!dut.rx_valid_o || dut.rx_flit_o[0] != expected) fail("FIFO order mismatch");
    tick(dut);
  }
  dut.rx_ready_i = 0;
  if (dut.rx_valid_o || dut.credits_o != 4) fail("credits did not return");

  drive_word(dut, 9);
  dut.tx_valid_i = 1;
  tick(dut);
  dut.tx_valid_i = 0;
  dut.flush_i = 1;
  tick(dut);
  dut.flush_i = 0;
  if (dut.rx_valid_o || dut.credits_o != 4) fail("flush did not restore credits");

  std::cout << "credit link directed tests passed\n";
  return 0;
}
