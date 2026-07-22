module rcif_mac_tile #(
  parameter int LANES = 4,
  parameter int ACC_W = 32
) (
  input  logic [(8*LANES)-1:0]          activation_i,
  input  logic signed [(9*LANES)-1:0]   weight_i,
  output logic signed [ACC_W-1:0]       accumulator_o
);
  logic signed [ACC_W-1:0] sum;
  logic signed [7:0] activation_lane;
  logic signed [8:0] weight_lane;
  logic signed [16:0] product;

  always_comb begin
    sum = '0;
    for (int lane = 0; lane < LANES; lane++) begin
      activation_lane = $signed(activation_i[(lane*8) +: 8]);
      weight_lane = $signed(weight_i[(lane*9) +: 9]);
      product = activation_lane * weight_lane;
      sum = sum + ACC_W'(product);
    end
    accumulator_o = sum;
  end
endmodule
