module rcif_cmd_queue #(
  parameter int DATA_W = 64,
  parameter int REQ_ID_W = 32
) (
  input  logic                clk_i,
  input  logic                rst_ni,

  input  logic                enq_valid_i,
  output logic                enq_ready_o,
  input  logic [REQ_ID_W-1:0] enq_request_id_i,
  input  logic [15:0]         enq_opcode_i,
  input  logic [15:0]         enq_flags_i,
  input  logic [DATA_W-1:0]   enq_payload_i,

  output logic                deq_valid_o,
  input  logic                deq_ready_i,
  output logic [REQ_ID_W-1:0] deq_request_id_o,
  output logic [15:0]         deq_opcode_o,
  output logic [15:0]         deq_flags_o,
  output logic [DATA_W-1:0]   deq_payload_o
);
  logic valid_q;
  logic [REQ_ID_W-1:0] request_id_q;
  logic [15:0] opcode_q;
  logic [15:0] flags_q;
  logic [DATA_W-1:0] payload_q;

  wire pop = valid_q && deq_ready_i;
  wire push = enq_valid_i && enq_ready_o;

  assign enq_ready_o = !valid_q || deq_ready_i;
  assign deq_valid_o = valid_q;
  assign deq_request_id_o = request_id_q;
  assign deq_opcode_o = opcode_q;
  assign deq_flags_o = flags_q;
  assign deq_payload_o = payload_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_q <= 1'b0;
      request_id_q <= '0;
      opcode_q <= '0;
      flags_q <= '0;
      payload_q <= '0;
    end else begin
      if (push) begin
        valid_q <= 1'b1;
        request_id_q <= enq_request_id_i;
        opcode_q <= enq_opcode_i;
        flags_q <= enq_flags_i;
        payload_q <= enq_payload_i;
      end else if (pop) begin
        valid_q <= 1'b0;
      end
    end
  end
endmodule

