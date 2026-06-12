module rcif_gather_scatter #(
  parameter int DATA_W = 64,
  parameter int STATUS_W = 32,
  parameter int PAGE_W = 16,
  parameter int LENGTH_W = 16,
  parameter int PAGE_COUNT = 256
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,

  input  logic                    req_valid_i,
  output logic                    req_ready_o,
  input  logic [PAGE_W-1:0]       req_src_page_i,
  input  logic [PAGE_W-1:0]       req_dst_page_i,
  input  logic [LENGTH_W-1:0]     req_length_i,

  output logic                    rsp_valid_o,
  input  logic                    rsp_ready_i,
  output logic [STATUS_W-1:0]     rsp_status_o,
  output logic [DATA_W-1:0]       rsp_result_o
);
  import rcif_desc_pkg::*;

  typedef enum logic [1:0] {
    IDLE,
    COPY,
    RESPOND
  } state_t;

  localparam int PAGE_IDX_W = (PAGE_COUNT <= 1) ? 1 : $clog2(PAGE_COUNT);

  state_t state_q;
  logic [PAGE_W-1:0] src_page_q;
  logic [PAGE_W-1:0] dst_page_q;
  logic [LENGTH_W-1:0] length_q;
  logic [LENGTH_W-1:0] copy_index_q;
  logic [DATA_W-1:0] checksum_q;
  logic [STATUS_W-1:0] rsp_status_q;
  logic [DATA_W-1:0] rsp_result_q;
  logic [DATA_W-1:0] page_mem [PAGE_COUNT];
  logic [PAGE_COUNT-1:0] page_valid_q;

  logic [PAGE_IDX_W-1:0] src_index;
  logic [PAGE_IDX_W-1:0] dst_index;
  logic [PAGE_W-1:0] copy_src_page;
  logic [DATA_W-1:0] copy_data;
  logic request_in_range;

  assign copy_src_page = src_page_q + PAGE_W'(copy_index_q);
  assign src_index = PAGE_IDX_W'(copy_src_page);
  assign dst_index = PAGE_IDX_W'(dst_page_q + PAGE_W'(copy_index_q));
  assign copy_data = page_valid_q[src_index] ? page_mem[src_index] : seed_page(copy_src_page);
  assign request_in_range = (int'(req_src_page_i) + int'(req_length_i) <= PAGE_COUNT) &&
                            (int'(req_dst_page_i) + int'(req_length_i) <= PAGE_COUNT);

  assign req_ready_o = (state_q == IDLE);
  assign rsp_valid_o = (state_q == RESPOND);
  assign rsp_status_o = rsp_status_q;
  assign rsp_result_o = rsp_result_q;

  function automatic logic [DATA_W-1:0] seed_page(input logic [PAGE_W-1:0] page);
    seed_page = DATA_W'(64'h9e37_79b9_7f4a_7c15) ^ DATA_W'(page);
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      src_page_q <= '0;
      dst_page_q <= '0;
      length_q <= '0;
      copy_index_q <= '0;
      checksum_q <= '0;
      rsp_status_q <= '0;
      rsp_result_q <= '0;
      page_valid_q <= '0;
    end else begin
      unique case (state_q)
        IDLE: begin
          if (req_valid_i) begin
            if (req_length_i == '0) begin
              rsp_status_q <= RCIF_STATUS_DMA_ZERO_LENGTH[STATUS_W-1:0];
              rsp_result_q <= '0;
              state_q <= RESPOND;
            end else if (!request_in_range) begin
              rsp_status_q <= RCIF_STATUS_DMA_RANGE[STATUS_W-1:0];
              rsp_result_q <= '0;
              state_q <= RESPOND;
            end else begin
              src_page_q <= req_src_page_i;
              dst_page_q <= req_dst_page_i;
              length_q <= req_length_i;
              copy_index_q <= '0;
              checksum_q <= '0;
              state_q <= COPY;
            end
          end
        end
        COPY: begin
          page_mem[dst_index] <= copy_data;
          page_valid_q[dst_index] <= 1'b1;
          checksum_q <= checksum_q ^ copy_data;
          if (copy_index_q == (length_q - 1'b1)) begin
            rsp_status_q <= RCIF_STATUS_OK[STATUS_W-1:0];
            rsp_result_q <= checksum_q ^ copy_data;
            state_q <= RESPOND;
          end else begin
            copy_index_q <= copy_index_q + 1'b1;
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

`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert(PAGE_COUNT > 0);
    end
  end
`endif
endmodule
