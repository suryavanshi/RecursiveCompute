module rcif_dma #(
  parameter int DATA_W = 64,
  parameter int STATUS_W = 32,
  parameter int PAGE_COUNT = 256
) (
  input  logic                clk_i,
  input  logic                rst_ni,

  input  logic                req_valid_i,
  output logic                req_ready_o,
  input  logic [15:0]         req_opcode_i,
  input  logic [DATA_W-1:0]   req_payload_i,

  output logic                rsp_valid_o,
  input  logic                rsp_ready_i,
  output logic [STATUS_W-1:0] rsp_status_o,
  output logic [DATA_W-1:0]   rsp_result_o
);
  import rcif_desc_pkg::*;

  typedef enum logic [1:0] {
    IDLE,
    WAIT_FETCH,
    WAIT_GATHER,
    RESPOND
  } state_t;

  state_t state_q;
  logic [STATUS_W-1:0] rsp_status_q;
  logic [DATA_W-1:0] rsp_result_q;

  logic [RCIF_DMA_SRC_PAGE_W-1:0] req_src_page;
  logic [RCIF_DMA_DST_PAGE_W-1:0] req_dst_page;
  logic [RCIF_DMA_LENGTH_W-1:0] req_length;
  logic req_reserved_bits_clear;
  logic req_is_dma_copy;
  logic req_is_dma_gather;
  logic req_is_index_write;
  logic req_is_ecc_inject;
  logic req_uses_gather;
  logic req_reserved_bits_clear_index;
  logic req_reserved_bits_clear_ecc;
  logic [RCIF_DMA_INDEX_SLOT_W-1:0] req_index_slot;
  logic [RCIF_DMA_INDEX_PAGE_W-1:0] req_index_page;
  logic desc_submit_valid;
  logic desc_submit_ready;
  logic desc_fetch_valid;
  logic desc_fetch_ready;
  logic [RCIF_DMA_SRC_PAGE_W-1:0] desc_src_page;
  logic [RCIF_DMA_DST_PAGE_W-1:0] desc_dst_page;
  logic [RCIF_DMA_LENGTH_W-1:0] desc_length;
  logic desc_indirect;
  logic gather_index_write_valid;
  logic gather_index_write_ready;
  logic gather_ecc_inject_valid;
  logic gather_ecc_inject_ready;
  logic gather_req_valid;
  logic gather_req_ready;
  logic gather_rsp_valid;
  logic gather_rsp_ready;
  logic [STATUS_W-1:0] gather_rsp_status;
  logic [DATA_W-1:0] gather_rsp_result;

  assign req_src_page = req_payload_i[RCIF_DMA_SRC_PAGE_LSB +: RCIF_DMA_SRC_PAGE_W];
  assign req_dst_page = req_payload_i[RCIF_DMA_DST_PAGE_LSB +: RCIF_DMA_DST_PAGE_W];
  assign req_length = req_payload_i[RCIF_DMA_LENGTH_LSB +: RCIF_DMA_LENGTH_W];
  assign req_reserved_bits_clear = (req_payload_i[DATA_W-1:48] == '0);
  assign req_is_dma_copy = (req_opcode_i == RCIF_OPCODE_DMA_COPY);
  assign req_is_dma_gather = (req_opcode_i == RCIF_OPCODE_DMA_GATHER);
  assign req_is_index_write = (req_opcode_i == RCIF_OPCODE_DMA_INDEX_WRITE);
  assign req_is_ecc_inject = (req_opcode_i == RCIF_OPCODE_DMA_ECC_INJECT);
  assign req_reserved_bits_clear_index = (req_payload_i[DATA_W-1:24] == '0);
  assign req_reserved_bits_clear_ecc = (req_payload_i[DATA_W-1:16] == '0);
  assign req_index_slot = req_payload_i[RCIF_DMA_INDEX_SLOT_LSB +: RCIF_DMA_INDEX_SLOT_W];
  assign req_index_page = req_payload_i[RCIF_DMA_INDEX_PAGE_LSB +: RCIF_DMA_INDEX_PAGE_W];
  assign req_uses_gather = (req_is_dma_copy || req_is_dma_gather) &&
                           req_reserved_bits_clear && (req_length != '0);

  assign req_ready_o = (state_q == IDLE) &&
                       (!req_uses_gather || desc_submit_ready) &&
                       (!req_is_index_write || gather_index_write_ready) &&
                       (!req_is_ecc_inject || gather_ecc_inject_ready);
  assign rsp_valid_o = (state_q == RESPOND);
  assign rsp_status_o = rsp_status_q;
  assign rsp_result_o = rsp_result_q;
  assign desc_submit_valid = req_valid_i && req_ready_o && req_uses_gather;
  assign desc_fetch_ready = (state_q == WAIT_FETCH) && gather_req_ready;
  assign gather_req_valid = (state_q == WAIT_FETCH) && desc_fetch_valid;
  assign gather_rsp_ready = (state_q == WAIT_GATHER);
  assign gather_index_write_valid = req_valid_i && req_ready_o && req_is_index_write &&
                                    req_reserved_bits_clear_index &&
                                    (int'(req_index_page) < PAGE_COUNT);
  assign gather_ecc_inject_valid = req_valid_i && req_ready_o && req_is_ecc_inject &&
                                   req_reserved_bits_clear_ecc &&
                                   (int'(req_src_page) < PAGE_COUNT);

  function automatic logic [DATA_W-1:0] pack_desc(
    input logic [RCIF_DMA_SRC_PAGE_W-1:0] src_page,
    input logic [RCIF_DMA_DST_PAGE_W-1:0] dst_page,
    input logic [RCIF_DMA_LENGTH_W-1:0] length
  );
    logic [DATA_W-1:0] desc_bits;
    begin
      desc_bits = '0;
      desc_bits[RCIF_DMA_SRC_PAGE_LSB +: RCIF_DMA_SRC_PAGE_W] = src_page;
      desc_bits[RCIF_DMA_DST_PAGE_LSB +: RCIF_DMA_DST_PAGE_W] = dst_page;
      desc_bits[RCIF_DMA_LENGTH_LSB +: RCIF_DMA_LENGTH_W] = length;
      pack_desc = desc_bits;
    end
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      rsp_status_q <= '0;
      rsp_result_q <= '0;
    end else begin
      unique case (state_q)
        IDLE: begin
          if (req_valid_i && req_ready_o) begin
            if (req_is_index_write && !req_reserved_bits_clear_index) begin
              rsp_status_q <= RCIF_STATUS_DMA_RESERVED_BITS[STATUS_W-1:0];
              rsp_result_q <= req_payload_i;
              state_q <= RESPOND;
            end else if (req_is_ecc_inject && !req_reserved_bits_clear_ecc) begin
              rsp_status_q <= RCIF_STATUS_DMA_RESERVED_BITS[STATUS_W-1:0];
              rsp_result_q <= req_payload_i;
              state_q <= RESPOND;
            end else if (!req_is_index_write && !req_is_ecc_inject &&
                         !req_reserved_bits_clear) begin
              rsp_status_q <= RCIF_STATUS_DMA_RESERVED_BITS[STATUS_W-1:0];
              rsp_result_q <= req_payload_i;
              state_q <= RESPOND;
            end else begin
              unique case (req_opcode_i)
                RCIF_OPCODE_DMA_COPY,
                RCIF_OPCODE_DMA_GATHER: begin
                  if (req_length == '0) begin
                    rsp_status_q <= RCIF_STATUS_DMA_ZERO_LENGTH[STATUS_W-1:0];
                    rsp_result_q <= pack_desc(req_src_page, req_dst_page, req_length);
                    state_q <= RESPOND;
                  end else begin
                    state_q <= WAIT_FETCH;
                  end
                end
                RCIF_OPCODE_DMA_INDEX_WRITE: begin
                  if (int'(req_index_page) >= PAGE_COUNT) begin
                    rsp_status_q <= RCIF_STATUS_DMA_RANGE[STATUS_W-1:0];
                    rsp_result_q <= req_payload_i;
                  end else begin
                    rsp_status_q <= RCIF_STATUS_OK[STATUS_W-1:0];
                    rsp_result_q <= req_payload_i;
                  end
                  state_q <= RESPOND;
                end
                RCIF_OPCODE_DMA_ECC_INJECT: begin
                  if (int'(req_src_page) >= PAGE_COUNT) begin
                    rsp_status_q <= RCIF_STATUS_DMA_RANGE[STATUS_W-1:0];
                    rsp_result_q <= req_payload_i;
                  end else begin
                    rsp_status_q <= RCIF_STATUS_OK[STATUS_W-1:0];
                    rsp_result_q <= req_payload_i;
                  end
                  state_q <= RESPOND;
                end
                default: begin
                  rsp_status_q <= RCIF_STATUS_UNSUPPORTED_OPCODE[STATUS_W-1:0];
                  rsp_result_q <= {{(DATA_W-16){1'b0}}, req_opcode_i};
                  state_q <= RESPOND;
                end
              endcase
            end
          end
        end
        WAIT_FETCH: begin
          if (desc_fetch_valid && desc_fetch_ready) begin
            state_q <= WAIT_GATHER;
          end
        end
        WAIT_GATHER: begin
          if (gather_rsp_valid) begin
            rsp_status_q <= gather_rsp_status;
            rsp_result_q <= gather_rsp_result;
            state_q <= RESPOND;
          end
        end
        RESPOND: begin
          if (rsp_ready_i) begin
            state_q <= IDLE;
          end
        end
        default: begin
          state_q <= IDLE;
        end
      endcase
    end
  end

  rcif_dma_desc_fetch #(
    .PAGE_W(RCIF_DMA_SRC_PAGE_W),
    .LENGTH_W(RCIF_DMA_LENGTH_W),
    .DEPTH(4)
  ) u_desc_fetch (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .submit_valid_i(desc_submit_valid),
    .submit_ready_o(desc_submit_ready),
    .submit_src_page_i(req_src_page),
    .submit_dst_page_i(req_dst_page),
    .submit_length_i(req_length),
    .submit_indirect_i(req_is_dma_gather),
    .fetch_valid_o(desc_fetch_valid),
    .fetch_ready_i(desc_fetch_ready),
    .fetch_src_page_o(desc_src_page),
    .fetch_dst_page_o(desc_dst_page),
    .fetch_length_o(desc_length),
    .fetch_indirect_o(desc_indirect)
  );

  rcif_gather_scatter #(
    .DATA_W(DATA_W),
    .STATUS_W(STATUS_W),
    .PAGE_W(RCIF_DMA_SRC_PAGE_W),
    .LENGTH_W(RCIF_DMA_LENGTH_W),
    .PAGE_COUNT(PAGE_COUNT)
  ) u_gather_scatter (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_valid_i(gather_req_valid),
    .req_ready_o(gather_req_ready),
    .req_src_page_i(desc_src_page),
    .req_dst_page_i(desc_dst_page),
    .req_length_i(desc_length),
    .req_indirect_i(desc_indirect),
    .index_write_valid_i(gather_index_write_valid),
    .index_write_ready_o(gather_index_write_ready),
    .index_write_slot_i(req_index_slot),
    .index_write_page_i(req_index_page),
    .ecc_inject_valid_i(gather_ecc_inject_valid),
    .ecc_inject_ready_o(gather_ecc_inject_ready),
    .ecc_inject_page_i(req_src_page),
    .rsp_valid_o(gather_rsp_valid),
    .rsp_ready_i(gather_rsp_ready),
    .rsp_status_o(gather_rsp_status),
    .rsp_result_o(gather_rsp_result)
  );
endmodule
