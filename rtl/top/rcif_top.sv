module rcif_top #(
  parameter int DATA_W = 64,
  parameter int REQ_ID_W = 32,
  parameter int STATUS_W = 32,
  parameter int CMD_QUEUE_DEPTH = 4,
  parameter int KV_MMU_ENTRIES = 8
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
  logic sched_cmd_valid;
  logic sched_cmd_ready;
  logic [REQ_ID_W-1:0] sched_cmd_request_id;
  logic [15:0] sched_cmd_opcode;
  logic [15:0] sched_cmd_flags;
  logic [DATA_W-1:0] sched_cmd_payload;

  rcif_cmd_queue #(
    .DATA_W(DATA_W),
    .REQ_ID_W(REQ_ID_W),
    .DEPTH(CMD_QUEUE_DEPTH)
  ) u_cmd_queue (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .enq_valid_i(cmd_valid_i),
    .enq_ready_o(cmd_ready_o),
    .enq_request_id_i(cmd_request_id_i),
    .enq_opcode_i(cmd_opcode_i),
    .enq_flags_i(cmd_flags_i),
    .enq_payload_i(cmd_payload_i),
    .deq_valid_o(sched_cmd_valid),
    .deq_ready_i(sched_cmd_ready),
    .deq_request_id_o(sched_cmd_request_id),
    .deq_opcode_o(sched_cmd_opcode),
    .deq_flags_o(sched_cmd_flags),
    .deq_payload_o(sched_cmd_payload)
  );

  rcif_scheduler_stub #(
    .DATA_W(DATA_W),
    .REQ_ID_W(REQ_ID_W),
    .STATUS_W(STATUS_W),
    .KV_MMU_ENTRIES(KV_MMU_ENTRIES)
  ) u_scheduler_stub (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .cmd_valid_i(sched_cmd_valid),
    .cmd_ready_o(sched_cmd_ready),
    .cmd_request_id_i(sched_cmd_request_id),
    .cmd_opcode_i(sched_cmd_opcode),
    .cmd_flags_i(sched_cmd_flags),
    .cmd_payload_i(sched_cmd_payload),
    .cpl_valid_o(cpl_valid_o),
    .cpl_ready_i(cpl_ready_i),
    .cpl_request_id_o(cpl_request_id_o),
    .cpl_status_o(cpl_status_o),
    .cpl_result_o(cpl_result_o)
  );

`ifndef SYNTHESIS
  rcif_top_assertions #(
    .REQ_ID_W(REQ_ID_W),
    .STATUS_W(STATUS_W),
    .DATA_W(DATA_W),
    .MAX_OUTSTANDING(CMD_QUEUE_DEPTH + 1)
  ) u_top_assertions (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .cmd_valid_i(cmd_valid_i),
    .cmd_ready_i(cmd_ready_o),
    .cpl_valid_i(cpl_valid_o),
    .cpl_ready_i(cpl_ready_i),
    .cpl_request_id_i(cpl_request_id_o),
    .cpl_status_i(cpl_status_o),
    .cpl_result_i(cpl_result_o)
  );
`endif
endmodule
