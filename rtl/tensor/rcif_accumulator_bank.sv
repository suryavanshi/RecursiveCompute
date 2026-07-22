module rcif_accumulator_bank #(
  parameter int LANES = 4,
  parameter int DATA_W = 16
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,
  input  logic                       clear_i,
  input  logic                       write_valid_i,
  input  logic [$clog2(LANES)-1:0]   write_index_i,
  input  logic signed [DATA_W-1:0]   write_data_i,
  output logic [(DATA_W*LANES)-1:0]  values_o
);
  logic signed [DATA_W-1:0] values_q [0:LANES-1];

  for (genvar lane = 0; lane < LANES; lane++) begin : gen_pack
    assign values_o[(lane*DATA_W) +: DATA_W] = values_q[lane];
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int lane = 0; lane < LANES; lane++) values_q[lane] <= '0;
    end else if (clear_i) begin
      for (int lane = 0; lane < LANES; lane++) values_q[lane] <= '0;
    end else if (write_valid_i) begin
      values_q[write_index_i] <= write_data_i;
    end
  end
endmodule
