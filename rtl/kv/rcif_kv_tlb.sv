module rcif_kv_tlb #(
  parameter int VIRT_PAGE_W = 16,
  parameter int PHYS_PAGE_W = 16,
  parameter int TIER_W = 4,
  parameter int FORMAT_W = 4,
  parameter int ENTRIES = 8
) (
  input  logic                              clk_i,
  input  logic                              rst_ni,

  input  logic [VIRT_PAGE_W-1:0]            lookup_virt_page_i,
  output logic                              lookup_hit_o,
  output logic [PHYS_PAGE_W-1:0]            lookup_phys_page_o,
  output logic [TIER_W-1:0]                 lookup_tier_o,
  output logic [FORMAT_W-1:0]               lookup_format_o,

  input  logic                              map_valid_i,
  input  logic [VIRT_PAGE_W-1:0]            map_virt_page_i,
  input  logic [PHYS_PAGE_W-1:0]            map_phys_page_i,
  input  logic [TIER_W-1:0]                 map_tier_i,
  input  logic [FORMAT_W-1:0]               map_format_i,
  output logic                              map_ready_o
);
  localparam int IDX_W = (ENTRIES <= 1) ? 1 : $clog2(ENTRIES);

  logic valid_q [ENTRIES];
  logic [VIRT_PAGE_W-1:0] virt_page_q [ENTRIES];
  logic [PHYS_PAGE_W-1:0] phys_page_q [ENTRIES];
  logic [TIER_W-1:0] tier_q [ENTRIES];
  logic [FORMAT_W-1:0] format_q [ENTRIES];

  logic lookup_hit;
  logic [IDX_W-1:0] lookup_index;
  logic map_hit;
  logic [IDX_W-1:0] map_hit_index;
  logic free_found;
  logic [IDX_W-1:0] free_index;
  logic [IDX_W-1:0] map_index;
  logic [IDX_W-1:0] replace_index_q;

  assign map_ready_o = 1'b1;
  assign map_index = map_hit ? map_hit_index : (free_found ? free_index : replace_index_q);

  always_comb begin
    lookup_hit = 1'b0;
    lookup_index = '0;
    map_hit = 1'b0;
    map_hit_index = '0;
    free_found = 1'b0;
    free_index = '0;

    for (int idx = 0; idx < ENTRIES; idx++) begin
      if (valid_q[idx] && virt_page_q[idx] == lookup_virt_page_i && !lookup_hit) begin
        lookup_hit = 1'b1;
        lookup_index = IDX_W'(idx);
      end
      if (valid_q[idx] && virt_page_q[idx] == map_virt_page_i && !map_hit) begin
        map_hit = 1'b1;
        map_hit_index = IDX_W'(idx);
      end
      if (!valid_q[idx] && !free_found) begin
        free_found = 1'b1;
        free_index = IDX_W'(idx);
      end
    end
  end

  assign lookup_hit_o = lookup_hit;
  assign lookup_phys_page_o = lookup_hit ? phys_page_q[lookup_index] : '0;
  assign lookup_tier_o = lookup_hit ? tier_q[lookup_index] : '0;
  assign lookup_format_o = lookup_hit ? format_q[lookup_index] : '0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      replace_index_q <= '0;
      for (int idx = 0; idx < ENTRIES; idx++) begin
        valid_q[idx] <= 1'b0;
        virt_page_q[idx] <= '0;
        phys_page_q[idx] <= '0;
        tier_q[idx] <= '0;
        format_q[idx] <= '0;
      end
    end else if (map_valid_i && map_ready_o) begin
      valid_q[map_index] <= 1'b1;
      virt_page_q[map_index] <= map_virt_page_i;
      phys_page_q[map_index] <= map_phys_page_i;
      tier_q[map_index] <= map_tier_i;
      format_q[map_index] <= map_format_i;
      if (!map_hit && !free_found) begin
        if (replace_index_q == IDX_W'(ENTRIES - 1)) begin
          replace_index_q <= '0;
        end else begin
          replace_index_q <= replace_index_q + 1'b1;
        end
      end
    end
  end

`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert(ENTRIES > 0);
    end
  end
`endif
endmodule
