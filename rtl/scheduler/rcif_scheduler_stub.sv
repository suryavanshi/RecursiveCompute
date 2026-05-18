module rcif_scheduler_stub #(
  parameter int DATA_W = 64,
  parameter int REQ_ID_W = 32,
  parameter int STATUS_W = 32
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic                  cmd_valid_i,
  output logic                  cmd_ready_o,
  input  logic [REQ_ID_W-1:0]   cmd_request_id_i,
  input  logic [15:0]           cmd_opcode_i,
  input  logic [15:0]           cmd_flags_i,
  input  logic [DATA_W-1:0]     cmd_payload_i,

  output logic                  cpl_valid_o,
  input  logic                  cpl_ready_i,
  output logic [REQ_ID_W-1:0]   cpl_request_id_o,
  output logic [STATUS_W-1:0]   cpl_status_o,
  output logic [DATA_W-1:0]     cpl_result_o
);
  localparam logic [15:0] OPCODE_NOP  = 16'h0000;
  localparam logic [15:0] OPCODE_ECHO = 16'h0001;

  localparam logic [STATUS_W-1:0] STATUS_OK = '0;
  localparam logic [STATUS_W-1:0] STATUS_UNSUPPORTED_OPCODE = {{(STATUS_W-1){1'b0}}, 1'b1};
  localparam logic [STATUS_W-1:0] STATUS_UNSUPPORTED_FLAGS = {{(STATUS_W-2){1'b0}}, 2'b10};

  typedef enum logic [0:0] {
    IDLE,
    RESPOND
  } state_t;

  state_t state_q, state_d;
  logic [REQ_ID_W-1:0] request_id_q, request_id_d;
  logic [STATUS_W-1:0] status_q, status_d;
  logic [DATA_W-1:0] result_q, result_d;

  always_comb begin
    state_d = state_q;
    request_id_d = request_id_q;
    status_d = status_q;
    result_d = result_q;

    cmd_ready_o = (state_q == IDLE);
    cpl_valid_o = (state_q == RESPOND);

    if (state_q == IDLE && cmd_valid_i) begin
      request_id_d = cmd_request_id_i;
      unique case (cmd_opcode_i)
        OPCODE_NOP: begin
          status_d = STATUS_OK;
          result_d = '0;
        end
        OPCODE_ECHO: begin
          status_d = STATUS_OK;
          result_d = cmd_payload_i;
        end
        default: begin
          status_d = STATUS_UNSUPPORTED_OPCODE;
          result_d = {{(DATA_W-16){1'b0}}, cmd_opcode_i};
        end
      endcase
      if (cmd_flags_i != 16'h0) begin
        status_d = STATUS_UNSUPPORTED_FLAGS;
      end
      state_d = RESPOND;
    end else if (state_q == RESPOND && cpl_ready_i) begin
      state_d = IDLE;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      request_id_q <= '0;
      status_q <= '0;
      result_q <= '0;
    end else begin
      state_q <= state_d;
      request_id_q <= request_id_d;
      status_q <= status_d;
      result_q <= result_d;
    end
  end

  assign cpl_request_id_o = request_id_q;
  assign cpl_status_o = status_q;
  assign cpl_result_o = result_q;
endmodule

