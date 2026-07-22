module rcif_kv_fault_unit #(
  parameter int REQ_ID_W = 32,
  parameter int VIRT_PAGE_W = 16,
  parameter int CAUSE_W = 16,
  parameter int DEPTH = 4
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,

  input  logic                         push_valid_i,
  output logic                         push_ready_o,
  input  logic [REQ_ID_W-1:0]          push_request_id_i,
  input  logic [VIRT_PAGE_W-1:0]       push_virt_page_i,
  input  logic [CAUSE_W-1:0]           push_cause_i,
  output logic                         overflow_o,

  output logic                         pop_valid_o,
  input  logic                         pop_ready_i,
  output logic [REQ_ID_W-1:0]          pop_request_id_o,
  output logic [VIRT_PAGE_W-1:0]       pop_virt_page_o,
  output logic [CAUSE_W-1:0]           pop_cause_o
);
  localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
  localparam int COUNT_W = $clog2(DEPTH + 1);
  localparam logic [COUNT_W-1:0] DEPTH_COUNT = COUNT_W'(DEPTH);
  localparam logic [PTR_W-1:0] LAST_PTR = PTR_W'(DEPTH - 1);

  logic [REQ_ID_W-1:0] request_id_mem [DEPTH];
  logic [VIRT_PAGE_W-1:0] virt_page_mem [DEPTH];
  logic [CAUSE_W-1:0] cause_mem [DEPTH];
  logic [PTR_W-1:0] rd_ptr_q;
  logic [PTR_W-1:0] wr_ptr_q;
  logic [COUNT_W-1:0] count_q;

  logic push;
  logic pop;
  logic full;

  assign full = (count_q == DEPTH_COUNT);
  assign push_ready_o = 1'b1;
  assign pop_valid_o = (count_q != '0);
  assign pop_request_id_o = request_id_mem[rd_ptr_q];
  assign pop_virt_page_o = virt_page_mem[rd_ptr_q];
  assign pop_cause_o = cause_mem[rd_ptr_q];

  assign push = push_valid_i && push_ready_o;
  assign pop = pop_valid_o && pop_ready_i;
  assign overflow_o = push && full && !pop;

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
        request_id_mem[wr_ptr_q] <= push_request_id_i;
        virt_page_mem[wr_ptr_q] <= push_virt_page_i;
        cause_mem[wr_ptr_q] <= push_cause_i;
        wr_ptr_q <= ptr_inc(wr_ptr_q);
      end

      if (pop || overflow_o) begin
        rd_ptr_q <= ptr_inc(rd_ptr_q);
      end

      unique case ({push, pop, overflow_o})
        3'b100: count_q <= count_q + 1'b1;
        3'b010: count_q <= count_q - 1'b1;
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
