module rcif_online_softmax #(
  parameter int SCORE_W = 32,
  parameter int ELEM_W = 8,
  parameter int VEC_LEN = 4,
  parameter int WEIGHT_W = 16,
  parameter int ACC_W = 48
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  logic                         start_i,
  input  logic                         step_valid_i,
  output logic                         step_ready_o,
  input  logic signed [SCORE_W-1:0]    step_score_i,
  input  logic [(ELEM_W*VEC_LEN)-1:0]  step_value_i,
  input  logic                         finish_i,
  output logic                         result_valid_o,
  input  logic                         result_ready_i,
  output logic                         result_empty_o,
  output logic [ACC_W-1:0]             result_denominator_o,
  output logic [(ACC_W*VEC_LEN)-1:0]   result_accumulator_o
);
  localparam logic [WEIGHT_W-1:0] ONE_WEIGHT = {1'b1, {(WEIGHT_W-1){1'b0}}};

  logic have_value_q;
  logic signed [SCORE_W-1:0] max_score_q;
  logic [ACC_W-1:0] denominator_q;
  logic signed [ACC_W-1:0] accumulator_q [0:VEC_LEN-1];
  logic result_valid_q;
  logic result_empty_q;
  logic [ACC_W-1:0] result_denominator_q;
  logic signed [ACC_W-1:0] result_accumulator_q [0:VEC_LEN-1];

  function automatic logic [WEIGHT_W-1:0] exp2_weight(
    input logic [SCORE_W-1:0] distance
  );
    int unsigned shift;
    begin
      shift = (distance >= (WEIGHT_W-1)) ? (WEIGHT_W-1) : distance;
      exp2_weight = ONE_WEIGHT >> shift;
    end
  endfunction

  assign step_ready_o = !result_valid_q;
  assign result_valid_o = result_valid_q;
  assign result_empty_o = result_empty_q;
  assign result_denominator_o = result_denominator_q;
  for (genvar dim = 0; dim < VEC_LEN; dim++) begin : gen_result_pack
    assign result_accumulator_o[(dim*ACC_W) +: ACC_W] = result_accumulator_q[dim];
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      have_value_q <= 1'b0;
      max_score_q <= '0;
      denominator_q <= '0;
      result_valid_q <= 1'b0;
      result_empty_q <= 1'b1;
      result_denominator_q <= '0;
      for (int dim = 0; dim < VEC_LEN; dim++) begin
        accumulator_q[dim] <= '0;
        result_accumulator_q[dim] <= '0;
      end
    end else begin
      if (result_valid_q && result_ready_i) begin
        result_valid_q <= 1'b0;
      end
      if (start_i) begin
        have_value_q <= 1'b0;
        max_score_q <= '0;
        denominator_q <= '0;
        for (int dim = 0; dim < VEC_LEN; dim++) begin
          accumulator_q[dim] <= '0;
        end
      end else if (step_valid_i && step_ready_o) begin
        if (!have_value_q) begin
          have_value_q <= 1'b1;
          max_score_q <= step_score_i;
          denominator_q <= ACC_W'(ONE_WEIGHT);
          for (int dim = 0; dim < VEC_LEN; dim++) begin
            accumulator_q[dim] <= $signed(step_value_i[(dim*ELEM_W) +: ELEM_W]) * $signed({1'b0, ONE_WEIGHT});
          end
        end else if (step_score_i > max_score_q) begin
          denominator_q <= ((denominator_q * exp2_weight(SCORE_W'(step_score_i - max_score_q))) >> (WEIGHT_W-1)) + ACC_W'(ONE_WEIGHT);
          for (int dim = 0; dim < VEC_LEN; dim++) begin
            accumulator_q[dim] <=
              (($signed(accumulator_q[dim]) * $signed({1'b0, exp2_weight(SCORE_W'(step_score_i - max_score_q))})) >>> (WEIGHT_W-1)) +
              ($signed(step_value_i[(dim*ELEM_W) +: ELEM_W]) * $signed({1'b0, ONE_WEIGHT}));
          end
          max_score_q <= step_score_i;
        end else begin
          denominator_q <= denominator_q + ACC_W'(exp2_weight(SCORE_W'(max_score_q - step_score_i)));
          for (int dim = 0; dim < VEC_LEN; dim++) begin
            accumulator_q[dim] <= accumulator_q[dim] +
              ($signed(step_value_i[(dim*ELEM_W) +: ELEM_W]) *
               $signed({1'b0, exp2_weight(SCORE_W'(max_score_q - step_score_i))}));
          end
        end
      end
      if (finish_i && !result_valid_q) begin
        result_valid_q <= 1'b1;
        result_empty_q <= !have_value_q;
        result_denominator_q <= denominator_q;
        for (int dim = 0; dim < VEC_LEN; dim++) begin
          result_accumulator_q[dim] <= accumulator_q[dim];
        end
      end
    end
  end
endmodule
