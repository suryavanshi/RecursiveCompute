module rcif_kv_mmu #(
  parameter int DATA_W = 64,
  parameter int STATUS_W = 32,
  parameter int ENTRIES = 8,
  parameter int TLB_ENTRIES = 4
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
    WAIT_WALK,
    RESPOND
  } state_t;

  state_t state_q;
  logic [STATUS_W-1:0] rsp_status_q;
  logic [DATA_W-1:0] rsp_result_q;

  logic [RCIF_KV_VIRT_PAGE_W-1:0] req_virt_page;
  logic [RCIF_KV_PHYS_PAGE_W-1:0] req_phys_page;
  logic [RCIF_KV_TIER_W-1:0] req_tier;
  logic [RCIF_KV_FORMAT_W-1:0] req_format;
  logic req_reserved_bits_clear;
  logic req_is_map;
  logic req_is_translate;
  logic accept_req;

  logic tlb_lookup_hit;
  logic [RCIF_KV_PHYS_PAGE_W-1:0] tlb_phys_page;
  logic [RCIF_KV_TIER_W-1:0] tlb_tier;
  logic [RCIF_KV_FORMAT_W-1:0] tlb_format;
  logic tlb_fill_valid;
  logic tlb_fill_ready;

  logic page_map_valid;
  logic page_map_ready;
  logic page_lookup_valid;
  logic page_lookup_ready;
  logic page_rsp_valid;
  logic page_rsp_ready;
  logic page_rsp_hit;
  logic [RCIF_KV_VIRT_PAGE_W-1:0] page_rsp_virt_page;
  logic [RCIF_KV_PHYS_PAGE_W-1:0] page_rsp_phys_page;
  logic [RCIF_KV_TIER_W-1:0] page_rsp_tier;
  logic [RCIF_KV_FORMAT_W-1:0] page_rsp_format;

  assign req_virt_page = req_payload_i[RCIF_KV_VIRT_PAGE_LSB +: RCIF_KV_VIRT_PAGE_W];
  assign req_phys_page = req_payload_i[RCIF_KV_PHYS_PAGE_LSB +: RCIF_KV_PHYS_PAGE_W];
  assign req_tier = req_payload_i[RCIF_KV_TIER_LSB +: RCIF_KV_TIER_W];
  assign req_format = req_payload_i[RCIF_KV_FORMAT_LSB +: RCIF_KV_FORMAT_W];
  assign req_reserved_bits_clear = (req_payload_i[DATA_W-1:40] == '0);
  assign req_is_map = (req_opcode_i == RCIF_OPCODE_KV_MAP);
  assign req_is_translate = (req_opcode_i == RCIF_OPCODE_KV_TRANSLATE);

  assign req_ready_o = (state_q == IDLE) &&
                       (!req_is_translate || tlb_lookup_hit || page_lookup_ready);
  assign accept_req = req_valid_i && req_ready_o;
  assign rsp_valid_o = (state_q == RESPOND);
  assign rsp_status_o = rsp_status_q;
  assign rsp_result_o = rsp_result_q;

  assign page_map_valid = accept_req && req_reserved_bits_clear && req_is_map && page_map_ready;
  assign page_lookup_valid = accept_req && req_reserved_bits_clear && req_is_translate &&
                             !tlb_lookup_hit;
  assign page_rsp_ready = (state_q == WAIT_WALK);
  assign tlb_fill_valid = tlb_fill_ready &&
                          (page_map_valid ||
                           (page_rsp_valid && page_rsp_ready && page_rsp_hit));

  function automatic logic [DATA_W-1:0] pack_entry(
    input logic [RCIF_KV_VIRT_PAGE_W-1:0] virt_page,
    input logic [RCIF_KV_PHYS_PAGE_W-1:0] phys_page,
    input logic [RCIF_KV_TIER_W-1:0] tier,
    input logic [RCIF_KV_FORMAT_W-1:0] format
  );
    logic [DATA_W-1:0] entry_bits;
    begin
      entry_bits = '0;
      entry_bits[RCIF_KV_VIRT_PAGE_LSB +: RCIF_KV_VIRT_PAGE_W] = virt_page;
      entry_bits[RCIF_KV_PHYS_PAGE_LSB +: RCIF_KV_PHYS_PAGE_W] = phys_page;
      entry_bits[RCIF_KV_TIER_LSB +: RCIF_KV_TIER_W] = tier;
      entry_bits[RCIF_KV_FORMAT_LSB +: RCIF_KV_FORMAT_W] = format;
      pack_entry = entry_bits;
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
          if (accept_req) begin
            if (!req_reserved_bits_clear) begin
              rsp_status_q <= RCIF_STATUS_KV_RESERVED_BITS[STATUS_W-1:0];
              rsp_result_q <= req_payload_i;
              state_q <= RESPOND;
            end else begin
              unique case (req_opcode_i)
                RCIF_OPCODE_KV_MAP: begin
                  rsp_status_q <= page_map_ready ?
                    RCIF_STATUS_OK[STATUS_W-1:0] : RCIF_STATUS_KV_FULL[STATUS_W-1:0];
                  rsp_result_q <= pack_entry(req_virt_page, req_phys_page, req_tier, req_format);
                  state_q <= RESPOND;
                end
                RCIF_OPCODE_KV_TRANSLATE: begin
                  if (tlb_lookup_hit) begin
                    rsp_status_q <= RCIF_STATUS_OK[STATUS_W-1:0];
                    rsp_result_q <= pack_entry(req_virt_page, tlb_phys_page, tlb_tier, tlb_format);
                    state_q <= RESPOND;
                  end else begin
                    state_q <= WAIT_WALK;
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
        WAIT_WALK: begin
          if (page_rsp_valid) begin
            rsp_status_q <= page_rsp_hit ?
              RCIF_STATUS_OK[STATUS_W-1:0] : RCIF_STATUS_KV_MISS[STATUS_W-1:0];
            rsp_result_q <= pack_entry(
              page_rsp_virt_page,
              page_rsp_phys_page,
              page_rsp_tier,
              page_rsp_format
            );
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

  rcif_kv_tlb #(
    .VIRT_PAGE_W(RCIF_KV_VIRT_PAGE_W),
    .PHYS_PAGE_W(RCIF_KV_PHYS_PAGE_W),
    .TIER_W(RCIF_KV_TIER_W),
    .FORMAT_W(RCIF_KV_FORMAT_W),
    .ENTRIES(TLB_ENTRIES)
  ) u_tlb (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .lookup_virt_page_i(req_virt_page),
    .lookup_hit_o(tlb_lookup_hit),
    .lookup_phys_page_o(tlb_phys_page),
    .lookup_tier_o(tlb_tier),
    .lookup_format_o(tlb_format),
    .map_valid_i(tlb_fill_valid),
    .map_virt_page_i(page_rsp_valid ? page_rsp_virt_page : req_virt_page),
    .map_phys_page_i(page_rsp_valid ? page_rsp_phys_page : req_phys_page),
    .map_tier_i(page_rsp_valid ? page_rsp_tier : req_tier),
    .map_format_i(page_rsp_valid ? page_rsp_format : req_format),
    .map_ready_o(tlb_fill_ready)
  );

  rcif_kv_page_walker #(
    .VIRT_PAGE_W(RCIF_KV_VIRT_PAGE_W),
    .PHYS_PAGE_W(RCIF_KV_PHYS_PAGE_W),
    .TIER_W(RCIF_KV_TIER_W),
    .FORMAT_W(RCIF_KV_FORMAT_W),
    .ENTRIES(ENTRIES)
  ) u_page_walker (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .map_valid_i(page_map_valid),
    .map_ready_o(page_map_ready),
    .map_virt_page_i(req_virt_page),
    .map_phys_page_i(req_phys_page),
    .map_tier_i(req_tier),
    .map_format_i(req_format),
    .lookup_valid_i(page_lookup_valid),
    .lookup_ready_o(page_lookup_ready),
    .lookup_virt_page_i(req_virt_page),
    .rsp_valid_o(page_rsp_valid),
    .rsp_ready_i(page_rsp_ready),
    .rsp_hit_o(page_rsp_hit),
    .rsp_virt_page_o(page_rsp_virt_page),
    .rsp_phys_page_o(page_rsp_phys_page),
    .rsp_tier_o(page_rsp_tier),
    .rsp_format_o(page_rsp_format)
  );
endmodule
