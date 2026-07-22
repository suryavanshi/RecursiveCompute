module rcif_ddr_axi_reader #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 128
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic                 req_valid_i,
  output logic                 req_ready_o,
  input  logic [ADDR_W-1:0]    req_addr_i,
  input  logic [7:0]           req_beats_i,
  output logic                 data_valid_o,
  input  logic                 data_ready_i,
  output logic [DATA_W-1:0]    data_o,
  output logic                 data_last_o,
  output logic                 error_o,
  output logic [ADDR_W-1:0]    m_axi_araddr_o,
  output logic [7:0]           m_axi_arlen_o,
  output logic                 m_axi_arvalid_o,
  input  logic                 m_axi_arready_i,
  input  logic [DATA_W-1:0]    m_axi_rdata_i,
  input  logic [1:0]           m_axi_rresp_i,
  input  logic                 m_axi_rlast_i,
  input  logic                 m_axi_rvalid_i,
  output logic                 m_axi_rready_o
);
  typedef enum logic [1:0] {IDLE, ADDRESS, DATA} state_t;
  state_t state_q;
  logic [ADDR_W-1:0] address_q;
  logic [7:0] length_q;

  assign req_ready_o = (state_q == IDLE) && (req_beats_i != 0);
  assign m_axi_araddr_o = address_q;
  assign m_axi_arlen_o = length_q - 1'b1;
  assign m_axi_arvalid_o = (state_q == ADDRESS);
  assign m_axi_rready_o = (state_q == DATA) && data_ready_i;
  assign data_valid_o = (state_q == DATA) && m_axi_rvalid_i;
  assign data_o = m_axi_rdata_i;
  assign data_last_o = m_axi_rlast_i;
  assign error_o = data_valid_o && (m_axi_rresp_i != 2'b00);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      address_q <= '0;
      length_q <= '0;
    end else begin
      unique case (state_q)
        IDLE: if (req_valid_i && req_ready_o) begin
          address_q <= req_addr_i;
          length_q <= req_beats_i;
          state_q <= ADDRESS;
        end
        ADDRESS: if (m_axi_arvalid_o && m_axi_arready_i) state_q <= DATA;
        DATA: if (data_valid_o && data_ready_i && m_axi_rlast_i) state_q <= IDLE;
        default: state_q <= IDLE;
      endcase
    end
  end
endmodule
