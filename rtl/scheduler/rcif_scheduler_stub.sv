module rcif_scheduler_stub #(
  parameter int DATA_W = 64,
  parameter int REQ_ID_W = 32,
  parameter int STATUS_W = 32,
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
  import rcif_desc_pkg::*;

  typedef enum logic [1:0] {
    IDLE,
    WAIT_KV,
    WAIT_DMA,
    RESPOND
  } state_t;

  state_t state_q, state_d;
  logic [REQ_ID_W-1:0] request_id_q, request_id_d;
  logic [STATUS_W-1:0] status_q, status_d;
  logic [DATA_W-1:0] result_q, result_d;
  logic [DATA_W-1:0] accepted_count_q;
  logic [DATA_W-1:0] completed_count_q;
  logic [DATA_W-1:0] error_count_q;
  logic kv_req_valid;
  logic kv_req_ready;
  logic [15:0] kv_req_opcode;
  logic [DATA_W-1:0] kv_req_payload;
  logic kv_rsp_valid;
  logic kv_rsp_ready;
  logic [STATUS_W-1:0] kv_rsp_status;
  logic [DATA_W-1:0] kv_rsp_result;
  logic dma_req_valid;
  logic dma_req_ready;
  logic [15:0] dma_req_opcode;
  logic [DATA_W-1:0] dma_req_payload;
  logic dma_rsp_valid;
  logic dma_rsp_ready;
  logic [STATUS_W-1:0] dma_rsp_status;
  logic [DATA_W-1:0] dma_rsp_result;

  wire accept_cmd = cmd_valid_i && cmd_ready_o;
  wire complete_cpl = (state_q == RESPOND) && cpl_ready_i;
  wire cmd_is_kv = (cmd_opcode_i == RCIF_OPCODE_KV_MAP) || (cmd_opcode_i == RCIF_OPCODE_KV_TRANSLATE);
  wire cmd_is_dma = (cmd_opcode_i == RCIF_OPCODE_DMA_COPY);

  always_comb begin
    state_d = state_q;
    request_id_d = request_id_q;
    status_d = status_q;
    result_d = result_q;

    cmd_ready_o = (state_q == IDLE) &&
                  (!cmd_is_kv || kv_req_ready) &&
                  (!cmd_is_dma || dma_req_ready);
    cpl_valid_o = (state_q == RESPOND);
    kv_req_valid = accept_cmd && cmd_is_kv && (cmd_flags_i == 16'h0);
    kv_req_opcode = cmd_opcode_i;
    kv_req_payload = cmd_payload_i;
    kv_rsp_ready = (state_q == WAIT_KV);
    dma_req_valid = accept_cmd && cmd_is_dma && (cmd_flags_i == 16'h0);
    dma_req_opcode = cmd_opcode_i;
    dma_req_payload = cmd_payload_i;
    dma_rsp_ready = (state_q == WAIT_DMA);

    if (accept_cmd) begin
      request_id_d = cmd_request_id_i;
      unique case (cmd_opcode_i)
        RCIF_OPCODE_NOP: begin
          status_d = RCIF_STATUS_OK[STATUS_W-1:0];
          result_d = '0;
        end
        RCIF_OPCODE_ECHO: begin
          status_d = RCIF_STATUS_OK[STATUS_W-1:0];
          result_d = cmd_payload_i;
        end
        RCIF_OPCODE_GET_COUNTER: begin
          unique case (cmd_payload_i[7:0])
            RCIF_COUNTER_ACCEPTED: begin
              status_d = RCIF_STATUS_OK[STATUS_W-1:0];
              result_d = accepted_count_q;
            end
            RCIF_COUNTER_COMPLETED: begin
              status_d = RCIF_STATUS_OK[STATUS_W-1:0];
              result_d = completed_count_q;
            end
            RCIF_COUNTER_ERRORS: begin
              status_d = RCIF_STATUS_OK[STATUS_W-1:0];
              result_d = error_count_q;
            end
            default: begin
              status_d = RCIF_STATUS_UNSUPPORTED_COUNTER[STATUS_W-1:0];
              result_d = {{(DATA_W-8){1'b0}}, cmd_payload_i[7:0]};
            end
          endcase
        end
        RCIF_OPCODE_KV_MAP,
        RCIF_OPCODE_KV_TRANSLATE,
        RCIF_OPCODE_DMA_COPY: begin
          status_d = RCIF_STATUS_OK[STATUS_W-1:0];
          result_d = '0;
        end
        default: begin
          status_d = RCIF_STATUS_UNSUPPORTED_OPCODE[STATUS_W-1:0];
          result_d = {{(DATA_W-16){1'b0}}, cmd_opcode_i};
        end
      endcase
      if (cmd_flags_i != 16'h0) begin
        status_d = RCIF_STATUS_UNSUPPORTED_FLAGS[STATUS_W-1:0];
      end
      if (cmd_is_kv && cmd_flags_i == 16'h0) begin
        state_d = WAIT_KV;
      end else if (cmd_is_dma && cmd_flags_i == 16'h0) begin
        state_d = WAIT_DMA;
      end else begin
        state_d = RESPOND;
      end
    end else if (state_q == WAIT_KV && kv_rsp_valid) begin
      status_d = kv_rsp_status;
      result_d = kv_rsp_result;
      state_d = RESPOND;
    end else if (state_q == WAIT_DMA && dma_rsp_valid) begin
      status_d = dma_rsp_status;
      result_d = dma_rsp_result;
      state_d = RESPOND;
    end else if (complete_cpl) begin
      state_d = IDLE;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      request_id_q <= '0;
      status_q <= '0;
      result_q <= '0;
      accepted_count_q <= '0;
      completed_count_q <= '0;
      error_count_q <= '0;
    end else begin
      state_q <= state_d;
      request_id_q <= request_id_d;
      status_q <= status_d;
      result_q <= result_d;
      if (accept_cmd) begin
        accepted_count_q <= accepted_count_q + 1'b1;
        if (status_d != RCIF_STATUS_OK[STATUS_W-1:0]) begin
          error_count_q <= error_count_q + 1'b1;
        end
      end
      if (state_q == WAIT_KV && kv_rsp_valid && kv_rsp_status != RCIF_STATUS_OK[STATUS_W-1:0]) begin
        error_count_q <= error_count_q + 1'b1;
      end
      if (state_q == WAIT_DMA && dma_rsp_valid && dma_rsp_status != RCIF_STATUS_OK[STATUS_W-1:0]) begin
        error_count_q <= error_count_q + 1'b1;
      end
      if (complete_cpl) begin
        completed_count_q <= completed_count_q + 1'b1;
      end
    end
  end

  assign cpl_request_id_o = request_id_q;
  assign cpl_status_o = status_q;
  assign cpl_result_o = result_q;

  rcif_kv_mmu #(
    .DATA_W(DATA_W),
    .STATUS_W(STATUS_W),
    .ENTRIES(KV_MMU_ENTRIES)
  ) u_kv_mmu (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_valid_i(kv_req_valid),
    .req_ready_o(kv_req_ready),
    .req_opcode_i(kv_req_opcode),
    .req_payload_i(kv_req_payload),
    .rsp_valid_o(kv_rsp_valid),
    .rsp_ready_i(kv_rsp_ready),
    .rsp_status_o(kv_rsp_status),
    .rsp_result_o(kv_rsp_result)
  );

  rcif_dma #(
    .DATA_W(DATA_W),
    .STATUS_W(STATUS_W)
  ) u_dma (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_valid_i(dma_req_valid),
    .req_ready_o(dma_req_ready),
    .req_opcode_i(dma_req_opcode),
    .req_payload_i(dma_req_payload),
    .rsp_valid_o(dma_rsp_valid),
    .rsp_ready_i(dma_rsp_ready),
    .rsp_status_o(dma_rsp_status),
    .rsp_result_o(dma_rsp_result)
  );
endmodule
