module rcif_norm_unit #(
  parameter int LANES = 4,
  parameter int DATA_W = 16
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  logic                         req_valid_i,
  output logic                         req_ready_o,
  input  logic [(DATA_W*LANES)-1:0]    req_values_i,
  input  logic [(DATA_W*LANES)-1:0]    req_gain_q8_8_i,
  input  logic [15:0]                  req_epsilon_i,
  output logic                         rsp_valid_o,
  input  logic                         rsp_ready_i,
  output logic [(DATA_W*LANES)-1:0]    rsp_values_o,
  output logic [LANES-1:0]             rsp_saturated_o
);
  logic rsp_valid_q;
  logic signed [DATA_W-1:0] values_q [0:LANES-1];
  logic [LANES-1:0] saturated_q;
  logic [63:0] sum_square;
  logic [63:0] mean_square;
  logic [31:0] rms;
  logic signed [32:0] normalized_comb [0:LANES-1];
  logic signed [32:0] max_extended, min_extended;
  localparam logic signed [DATA_W-1:0] MAX_VALUE = {1'b0, {(DATA_W-1){1'b1}}};
  localparam logic signed [DATA_W-1:0] MIN_VALUE = {1'b1, {(DATA_W-1){1'b0}}};

  function automatic logic [31:0] integer_sqrt(input logic [63:0] value);
    logic [31:0] root;
    logic [31:0] trial;
    logic [63:0] trial_square;
    begin
      root = '0;
      for (int bit_index = 15; bit_index >= 0; bit_index--) begin
        trial = root | (32'(1) << bit_index);
        trial_square = trial * trial;
        if (trial_square <= value) root = trial;
      end
      integer_sqrt = root;
    end
  endfunction

  assign req_ready_o = !rsp_valid_q || rsp_ready_i;
  assign rsp_valid_o = rsp_valid_q;
  assign rsp_saturated_o = saturated_q;
  for (genvar lane = 0; lane < LANES; lane++) begin : gen_pack
    assign rsp_values_o[(lane*DATA_W) +: DATA_W] = values_q[lane];
  end

  always_comb begin
    sum_square = '0;
    for (int lane = 0; lane < LANES; lane++) begin
      sum_square = sum_square +
        ($signed(req_values_i[(lane*DATA_W) +: DATA_W]) *
         $signed(req_values_i[(lane*DATA_W) +: DATA_W]));
    end
    mean_square = (sum_square / 64'(LANES)) + 64'(req_epsilon_i);
    rms = integer_sqrt(mean_square);
    max_extended = {{(33-DATA_W){MAX_VALUE[DATA_W-1]}}, MAX_VALUE};
    min_extended = {{(33-DATA_W){MIN_VALUE[DATA_W-1]}}, MIN_VALUE};
    for (int lane = 0; lane < LANES; lane++) begin
      if (rms == 0) begin
        normalized_comb[lane] = '0;
      end else begin
        normalized_comb[lane] =
          $signed(req_values_i[(lane*DATA_W) +: DATA_W]) *
          $signed(req_gain_q8_8_i[(lane*DATA_W) +: DATA_W]) /
          $signed({1'b0, rms});
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_valid_q <= 1'b0;
      saturated_q <= '0;
      for (int lane = 0; lane < LANES; lane++) values_q[lane] <= '0;
    end else begin
      if (rsp_valid_q && rsp_ready_i) rsp_valid_q <= 1'b0;
      if (req_valid_i && req_ready_o) begin
        rsp_valid_q <= 1'b1;
        saturated_q <= '0;
        for (int lane = 0; lane < LANES; lane++) begin
          if (normalized_comb[lane] > max_extended) begin
            values_q[lane] <= MAX_VALUE;
            saturated_q[lane] <= 1'b1;
          end else if (normalized_comb[lane] < min_extended) begin
            values_q[lane] <= MIN_VALUE;
            saturated_q[lane] <= 1'b1;
          end else begin
            values_q[lane] <= normalized_comb[lane][DATA_W-1:0];
          end
        end
      end
    end
  end
endmodule
