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
  logic req_uses_gather;
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
  assign req_uses_gather = req_is_dma_copy && req_reserved_bits_clear && (req_length != '0);

  assign req_ready_o = (state_q == IDLE) && (!req_uses_gather || gather_req_ready);
  assign rsp_valid_o = (state_q == RESPOND);
  assign rsp_status_o = rsp_status_q;
  assign rsp_result_o = rsp_result_q;
  assign gather_req_valid = req_valid_i && req_ready_o && req_uses_gather;
  assign gather_rsp_ready = (state_q == WAIT_GATHER);

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
            if (!req_reserved_bits_clear) begin
              rsp_status_q <= RCIF_STATUS_DMA_RESERVED_BITS[STATUS_W-1:0];
              rsp_result_q <= req_payload_i;
              state_q <= RESPOND;
            end else begin
              unique case (req_opcode_i)
                RCIF_OPCODE_DMA_COPY: begin
                  if (req_length == '0) begin
                    rsp_status_q <= RCIF_STATUS_DMA_ZERO_LENGTH[STATUS_W-1:0];
                    rsp_result_q <= pack_desc(req_src_page, req_dst_page, req_length);
                    state_q <= RESPOND;
                  end else begin
                    state_q <= WAIT_GATHER;
                  end
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
    .req_src_page_i(req_src_page),
    .req_dst_page_i(req_dst_page),
    .req_length_i(req_length),
    .rsp_valid_o(gather_rsp_valid),
    .rsp_ready_i(gather_rsp_ready),
    .rsp_status_o(gather_rsp_status),
    .rsp_result_o(gather_rsp_result)
  );
endmodule
