module rcif_kv_mmu #(
  parameter int DATA_W = 64,
  parameter int STATUS_W = 32,
  parameter int ENTRIES = 8
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

  logic rsp_valid_q;
  logic [STATUS_W-1:0] rsp_status_q;
  logic [DATA_W-1:0] rsp_result_q;

  logic [RCIF_KV_VIRT_PAGE_W-1:0] req_virt_page;
  logic [RCIF_KV_PHYS_PAGE_W-1:0] req_phys_page;
  logic [RCIF_KV_TIER_W-1:0] req_tier;
  logic [RCIF_KV_FORMAT_W-1:0] req_format;
  logic req_reserved_bits_clear;
  logic tlb_lookup_hit;
  logic [RCIF_KV_PHYS_PAGE_W-1:0] tlb_phys_page;
  logic [RCIF_KV_TIER_W-1:0] tlb_tier;
  logic [RCIF_KV_FORMAT_W-1:0] tlb_format;
  logic tlb_map_valid;
  logic tlb_map_ready;

  assign req_virt_page = req_payload_i[RCIF_KV_VIRT_PAGE_LSB +: RCIF_KV_VIRT_PAGE_W];
  assign req_phys_page = req_payload_i[RCIF_KV_PHYS_PAGE_LSB +: RCIF_KV_PHYS_PAGE_W];
  assign req_tier = req_payload_i[RCIF_KV_TIER_LSB +: RCIF_KV_TIER_W];
  assign req_format = req_payload_i[RCIF_KV_FORMAT_LSB +: RCIF_KV_FORMAT_W];
  assign req_reserved_bits_clear = (req_payload_i[DATA_W-1:40] == '0);

  assign req_ready_o = !rsp_valid_q || rsp_ready_i;
  assign rsp_valid_o = rsp_valid_q;
  assign rsp_status_o = rsp_status_q;
  assign rsp_result_o = rsp_result_q;

  assign tlb_map_valid = req_valid_i &&
                         req_ready_o &&
                         req_reserved_bits_clear &&
                         req_opcode_i == RCIF_OPCODE_KV_MAP &&
                         tlb_map_ready;

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
      rsp_valid_q <= 1'b0;
      rsp_status_q <= '0;
      rsp_result_q <= '0;
    end else begin
      if (rsp_valid_q && rsp_ready_i) begin
        rsp_valid_q <= 1'b0;
      end

      if (req_valid_i && req_ready_o) begin
        rsp_valid_q <= 1'b1;
        if (!req_reserved_bits_clear) begin
          rsp_status_q <= RCIF_STATUS_KV_RESERVED_BITS[STATUS_W-1:0];
          rsp_result_q <= req_payload_i;
        end else begin
          unique case (req_opcode_i)
            RCIF_OPCODE_KV_MAP: begin
              if (tlb_map_ready) begin
                rsp_status_q <= RCIF_STATUS_OK[STATUS_W-1:0];
                rsp_result_q <= pack_entry(req_virt_page, req_phys_page, req_tier, req_format);
              end else begin
                rsp_status_q <= RCIF_STATUS_KV_FULL[STATUS_W-1:0];
                rsp_result_q <= pack_entry(req_virt_page, req_phys_page, req_tier, req_format);
              end
            end
            RCIF_OPCODE_KV_TRANSLATE: begin
              if (tlb_lookup_hit) begin
                rsp_status_q <= RCIF_STATUS_OK[STATUS_W-1:0];
                rsp_result_q <= pack_entry(
                  req_virt_page,
                  tlb_phys_page,
                  tlb_tier,
                  tlb_format
                );
              end else begin
                rsp_status_q <= RCIF_STATUS_KV_MISS[STATUS_W-1:0];
                rsp_result_q <= pack_entry(req_virt_page, '0, '0, '0);
              end
            end
            default: begin
              rsp_status_q <= RCIF_STATUS_UNSUPPORTED_OPCODE[STATUS_W-1:0];
              rsp_result_q <= {{(DATA_W-16){1'b0}}, req_opcode_i};
            end
          endcase
        end
      end
    end
  end

  rcif_kv_tlb #(
    .VIRT_PAGE_W(RCIF_KV_VIRT_PAGE_W),
    .PHYS_PAGE_W(RCIF_KV_PHYS_PAGE_W),
    .TIER_W(RCIF_KV_TIER_W),
    .FORMAT_W(RCIF_KV_FORMAT_W),
    .ENTRIES(ENTRIES)
  ) u_tlb (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .lookup_virt_page_i(req_virt_page),
    .lookup_hit_o(tlb_lookup_hit),
    .lookup_phys_page_o(tlb_phys_page),
    .lookup_tier_o(tlb_tier),
    .lookup_format_o(tlb_format),
    .map_valid_i(tlb_map_valid),
    .map_virt_page_i(req_virt_page),
    .map_phys_page_i(req_phys_page),
    .map_tier_i(req_tier),
    .map_format_i(req_format),
    .map_ready_o(tlb_map_ready)
  );
endmodule
