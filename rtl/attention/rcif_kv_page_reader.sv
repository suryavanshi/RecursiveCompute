module rcif_kv_page_reader #(
  parameter int ELEM_W = 8,
  parameter int VEC_LEN = 4,
  parameter int MAX_PAGES = 8,
  parameter int PAGE_TOKENS = 4,
  parameter int MAX_KV_HEADS = 4
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,

  input  logic                         page_write_valid_i,
  input  logic [$clog2(MAX_PAGES)-1:0] page_write_slot_i,
  input  logic [$clog2(MAX_PAGES)-1:0] page_write_phys_i,

  input  logic                         kv_write_valid_i,
  input  logic [$clog2(MAX_PAGES)-1:0] kv_write_phys_page_i,
  input  logic [$clog2(PAGE_TOKENS)-1:0] kv_write_offset_i,
  input  logic [$clog2(MAX_KV_HEADS)-1:0] kv_write_head_i,
  input  logic [(ELEM_W*VEC_LEN)-1:0]  kv_write_key_i,
  input  logic [(ELEM_W*VEC_LEN)-1:0]  kv_write_value_i,

  input  logic                         req_valid_i,
  output logic                         req_ready_o,
  input  logic [$clog2(MAX_PAGES*PAGE_TOKENS)-1:0] req_token_i,
  input  logic [$clog2(MAX_KV_HEADS)-1:0] req_head_i,

  output logic                         rsp_valid_o,
  input  logic                         rsp_ready_i,
  output logic [(ELEM_W*VEC_LEN)-1:0]  rsp_key_o,
  output logic [(ELEM_W*VEC_LEN)-1:0]  rsp_value_o
);
  localparam int VEC_W = ELEM_W * VEC_LEN;
  localparam int PAGE_W = $clog2(MAX_PAGES);
  localparam int OFFSET_W = $clog2(PAGE_TOKENS);

  logic [PAGE_W-1:0] page_list [0:MAX_PAGES-1];
  logic [VEC_W-1:0] key_mem [0:MAX_PAGES-1][0:PAGE_TOKENS-1][0:MAX_KV_HEADS-1];
  logic [VEC_W-1:0] value_mem [0:MAX_PAGES-1][0:PAGE_TOKENS-1][0:MAX_KV_HEADS-1];
  logic rsp_valid_q;
  logic [VEC_W-1:0] rsp_key_q, rsp_value_q;

  wire [PAGE_W-1:0] req_page_slot = PAGE_W'(req_token_i / PAGE_TOKENS);
  wire [OFFSET_W-1:0] req_offset = OFFSET_W'(req_token_i % PAGE_TOKENS);

  assign req_ready_o = !rsp_valid_q || rsp_ready_i;
  assign rsp_valid_o = rsp_valid_q;
  assign rsp_key_o = rsp_key_q;
  assign rsp_value_o = rsp_value_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_valid_q <= 1'b0;
      rsp_key_q <= '0;
      rsp_value_q <= '0;
      for (int page = 0; page < MAX_PAGES; page++) begin
        page_list[page] <= PAGE_W'(page);
      end
    end else begin
      if (page_write_valid_i) begin
        page_list[page_write_slot_i] <= page_write_phys_i;
      end
      if (kv_write_valid_i) begin
        key_mem[kv_write_phys_page_i][kv_write_offset_i][kv_write_head_i] <= kv_write_key_i;
        value_mem[kv_write_phys_page_i][kv_write_offset_i][kv_write_head_i] <= kv_write_value_i;
      end
      if (rsp_valid_q && rsp_ready_i) begin
        rsp_valid_q <= 1'b0;
      end
      if (req_valid_i && req_ready_o) begin
        rsp_valid_q <= 1'b1;
        rsp_key_q <= key_mem[page_list[req_page_slot]][req_offset][req_head_i];
        rsp_value_q <= value_mem[page_list[req_page_slot]][req_offset][req_head_i];
      end
    end
  end
endmodule
