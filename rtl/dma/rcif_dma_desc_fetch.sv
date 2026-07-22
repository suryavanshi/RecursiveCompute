module rcif_dma_desc_fetch #(
  parameter int PAGE_W = 16,
  parameter int LENGTH_W = 16,
  parameter int DEPTH = 4
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,

  input  logic                    submit_valid_i,
  output logic                    submit_ready_o,
  input  logic [PAGE_W-1:0]       submit_src_page_i,
  input  logic [PAGE_W-1:0]       submit_dst_page_i,
  input  logic [LENGTH_W-1:0]     submit_length_i,
  input  logic                    submit_indirect_i,

  output logic                    fetch_valid_o,
  input  logic                    fetch_ready_i,
  output logic [PAGE_W-1:0]       fetch_src_page_o,
  output logic [PAGE_W-1:0]       fetch_dst_page_o,
  output logic [LENGTH_W-1:0]     fetch_length_o,
  output logic                    fetch_indirect_o
);
  localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
  localparam int COUNT_W = $clog2(DEPTH + 1);
  localparam logic [COUNT_W-1:0] DEPTH_COUNT = COUNT_W'(DEPTH);
  localparam logic [PTR_W-1:0] LAST_PTR = PTR_W'(DEPTH - 1);

  logic [PAGE_W-1:0] src_page_mem [DEPTH];
  logic [PAGE_W-1:0] dst_page_mem [DEPTH];
  logic [LENGTH_W-1:0] length_mem [DEPTH];
  logic indirect_mem [DEPTH];
  logic [PTR_W-1:0] rd_ptr_q;
  logic [PTR_W-1:0] wr_ptr_q;
  logic [COUNT_W-1:0] count_q;

  logic push;
  logic pop;

  assign push = submit_valid_i && submit_ready_o;
  assign pop = fetch_valid_o && fetch_ready_i;

  assign submit_ready_o = (count_q < DEPTH_COUNT) || pop;
  assign fetch_valid_o = (count_q != '0);
  assign fetch_src_page_o = src_page_mem[rd_ptr_q];
  assign fetch_dst_page_o = dst_page_mem[rd_ptr_q];
  assign fetch_length_o = length_mem[rd_ptr_q];
  assign fetch_indirect_o = indirect_mem[rd_ptr_q];

  function automatic logic [PTR_W-1:0] ptr_inc(input logic [PTR_W-1:0] ptr);
    if (ptr == LAST_PTR) begin
      ptr_inc = '0;
    end else begin
      ptr_inc = ptr + 1'b1;
    end
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_ptr_q <= '0;
      wr_ptr_q <= '0;
      count_q <= '0;
    end else begin
      if (push) begin
        src_page_mem[wr_ptr_q] <= submit_src_page_i;
        dst_page_mem[wr_ptr_q] <= submit_dst_page_i;
        length_mem[wr_ptr_q] <= submit_length_i;
        indirect_mem[wr_ptr_q] <= submit_indirect_i;
        wr_ptr_q <= ptr_inc(wr_ptr_q);
      end
      if (pop) begin
        rd_ptr_q <= ptr_inc(rd_ptr_q);
      end

      unique case ({push, pop})
        2'b10: count_q <= count_q + 1'b1;
        2'b01: count_q <= count_q - 1'b1;
        default: count_q <= count_q;
      endcase
    end
  end

`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert(DEPTH > 0);
      assert(count_q <= DEPTH_COUNT);
    end
  end
`endif
endmodule
