module rcif_scale_apply #(
  parameter int ACC_W = 32,
  parameter int OUT_W = 16
) (
  input  logic signed [ACC_W-1:0] accumulator_i,
  input  logic signed [15:0]      scale_q8_8_i,
  input  logic signed [ACC_W-1:0] bias_i,
  output logic signed [OUT_W-1:0] result_o,
  output logic                    saturated_o
);
  logic signed [ACC_W+16-1:0] product;
  logic signed [ACC_W+16-1:0] rounded;
  logic signed [ACC_W+16-1:0] shifted;
  logic signed [ACC_W+16-1:0] biased;
  logic signed [ACC_W+16-1:0] bias_extended;
  logic signed [ACC_W+16-1:0] max_extended;
  logic signed [ACC_W+16-1:0] min_extended;
  localparam logic signed [OUT_W-1:0] MAX_VALUE = {1'b0, {(OUT_W-1){1'b1}}};
  localparam logic signed [OUT_W-1:0] MIN_VALUE = {1'b1, {(OUT_W-1){1'b0}}};

  always_comb begin
    bias_extended = {{16{bias_i[ACC_W-1]}}, bias_i};
    max_extended = {{(ACC_W+16-OUT_W){MAX_VALUE[OUT_W-1]}}, MAX_VALUE};
    min_extended = {{(ACC_W+16-OUT_W){MIN_VALUE[OUT_W-1]}}, MIN_VALUE};
    product = accumulator_i * scale_q8_8_i;
    if (product >= 0) begin
      rounded = product + (ACC_W+16)'(128);
    end else begin
      rounded = product + (ACC_W+16)'(127);
    end
    shifted = rounded >>> 8;
    biased = shifted + bias_extended;
    saturated_o = 1'b0;
    if (biased > max_extended) begin
      result_o = MAX_VALUE;
      saturated_o = 1'b1;
    end else if (biased < min_extended) begin
      result_o = MIN_VALUE;
      saturated_o = 1'b1;
    end else begin
      result_o = biased[OUT_W-1:0];
    end
  end
endmodule
