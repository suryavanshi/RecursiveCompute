#include <cstdint>
#include <iostream>

#include "Vrcif_ddr_axi_reader.h"

namespace {
void tick(Vrcif_ddr_axi_reader& dut) {
  dut.clk_i = 0;
  dut.eval();
  dut.clk_i = 1;
  dut.eval();
}

void reset(Vrcif_ddr_axi_reader& dut) {
  dut.rst_ni = 0;
  dut.req_valid_i = 0;
  dut.data_ready_i = 0;
  dut.m_axi_arready_i = 0;
  dut.m_axi_rvalid_i = 0;
  tick(dut);
  tick(dut);
  dut.rst_ni = 1;
  tick(dut);
}
}  // namespace

int main() {
  Vrcif_ddr_axi_reader dut;
  reset(dut);

  dut.req_addr_i = 0x1000;
  dut.req_beats_i = 3;
  dut.req_valid_i = 1;
  dut.eval();
  if (!dut.req_ready_o) return 1;
  tick(dut);
  dut.req_valid_i = 0;
  dut.eval();
  if (!dut.m_axi_arvalid_o || dut.m_axi_araddr_o != 0x1000 ||
      dut.m_axi_arlen_o != 2) return 2;
  dut.m_axi_arready_i = 1;
  tick(dut);
  dut.m_axi_arready_i = 0;

  for (uint32_t beat = 0; beat < 3; ++beat) {
    dut.m_axi_rvalid_i = 1;
    dut.m_axi_rdata_i[0] = 0x40 + beat;
    dut.m_axi_rdata_i[1] = 0;
    dut.m_axi_rdata_i[2] = 0;
    dut.m_axi_rdata_i[3] = 0;
    dut.m_axi_rresp_i = 0;
    dut.m_axi_rlast_i = beat == 2;
    dut.data_ready_i = 0;
    dut.eval();
    if (!dut.data_valid_o || dut.m_axi_rready_o) return 3;
    dut.data_ready_i = 1;
    dut.eval();
    if (!dut.m_axi_rready_o || dut.data_o[0] != 0x40 + beat ||
        static_cast<bool>(dut.data_last_o) != (beat == 2)) return 4;
    tick(dut);
  }
  dut.m_axi_rvalid_i = 0;
  dut.data_ready_i = 0;
  dut.eval();
  if (!dut.req_ready_o) return 5;

  std::cout << "phase10 ddr axi reader: PASS\n";
  return 0;
}
