module rcif_tensor_array #(
  parameter int LANES = 4,
  parameter int ACC_W = 32,
  parameter int OUT_W = 16
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,

  input  logic                         weight_write_valid_i,
  output logic                         weight_write_ready_o,
  input  logic [$clog2(LANES)-1:0]     weight_write_row_i,
  input  logic [1:0]                   weight_write_format_i,
  input  logic [31:0]                  weight_write_data_i,
  input  logic signed [7:0]            weight_write_zero_point_i,
  input  logic signed [15:0]           weight_write_scale_q8_8_i,
  input  logic signed [ACC_W-1:0]      weight_write_bias_i,
  input  logic signed [OUT_W-1:0]      weight_write_norm_gain_q8_8_i,

  input  logic                         req_valid_i,
  output logic                         req_ready_o,
  input  logic [(8*LANES)-1:0]         req_activation_i,
  input  logic [1:0]                   req_activation_mode_i,
  input  logic                         req_norm_enable_i,
  input  logic [15:0]                  req_norm_epsilon_i,

  output logic                         rsp_valid_o,
  input  logic                         rsp_ready_i,
  output logic [(OUT_W*LANES)-1:0]     rsp_result_o,
  output logic [LANES-1:0]             rsp_saturated_o,
  output logic                         rsp_config_error_o
);
  typedef enum logic [2:0] {IDLE, RUN, POST, WAIT_NORM, RESPOND} state_t;
  state_t state_q;

  logic [1:0] weight_format_mem [0:LANES-1];
  logic [31:0] weight_data_mem [0:LANES-1];
  logic signed [7:0] zero_point_mem [0:LANES-1];
  logic signed [15:0] scale_mem [0:LANES-1];
  logic signed [ACC_W-1:0] bias_mem [0:LANES-1];
  logic signed [OUT_W-1:0] norm_gain_mem [0:LANES-1];
  logic [LANES-1:0] weight_valid_q;
  logic [(8*LANES)-1:0] activation_q;
  logic [1:0] activation_mode_q;
  logic norm_enable_q;
  logic [15:0] norm_epsilon_q;
  logic [$clog2(LANES)-1:0] row_q;
  logic [LANES-1:0] saturated_q;
  logic config_error_q;

  logic signed [(9*LANES)-1:0] decoded_weight;
  logic weight_format_valid;
  logic signed [ACC_W-1:0] mac_accumulator;
  logic signed [OUT_W-1:0] scaled_result;
  logic scale_saturated;
  logic signed [OUT_W-1:0] activated_result;
  logic activation_mode_valid;
  logic bank_clear, bank_write;
  logic [(OUT_W*LANES)-1:0] bank_values;
  logic [(OUT_W*LANES)-1:0] norm_gains;
  logic norm_req_valid, norm_req_ready, norm_rsp_valid, norm_rsp_ready;
  logic [(OUT_W*LANES)-1:0] norm_rsp_values;
  logic [LANES-1:0] norm_rsp_saturated;
  logic all_weights_valid;
  logic all_formats_valid;
  logic request_config_valid;

  always_comb begin
    all_weights_valid = &weight_valid_q;
    all_formats_valid = 1'b1;
    norm_gains = '0;
    for (int row = 0; row < LANES; row++) begin
      if (weight_format_mem[row] > 2'd1) all_formats_valid = 1'b0;
      norm_gains[(row*OUT_W) +: OUT_W] = norm_gain_mem[row];
    end
    request_config_valid = all_weights_valid && all_formats_valid &&
                           (req_activation_mode_i <= 2'd2);
  end

  assign weight_write_ready_o = (state_q == IDLE);
  assign req_ready_o = (state_q == IDLE) && !weight_write_valid_i;
  assign bank_clear = req_valid_i && req_ready_o;
  assign bank_write = (state_q == RUN);
  assign norm_req_valid = (state_q == POST) && norm_enable_q;
  assign norm_rsp_ready = (state_q == WAIT_NORM) && rsp_ready_i;
  assign rsp_valid_o = ((state_q == RESPOND) && !norm_enable_q) ||
                       ((state_q == WAIT_NORM) && norm_rsp_valid);
  assign rsp_result_o = norm_enable_q ? norm_rsp_values : bank_values;
  assign rsp_saturated_o = saturated_q |
                           (norm_enable_q ? norm_rsp_saturated : '0);
  assign rsp_config_error_o = config_error_q;

  rcif_weight_decode #(.LANES(LANES)) u_weight_decode (
    .format_i(weight_format_mem[row_q]), .packed_weight_i(weight_data_mem[row_q]),
    .zero_point_i(zero_point_mem[row_q]), .decoded_weight_o(decoded_weight),
    .format_valid_o(weight_format_valid)
  );

  rcif_mac_tile #(.LANES(LANES), .ACC_W(ACC_W)) u_mac_tile (
    .activation_i(activation_q), .weight_i(decoded_weight),
    .accumulator_o(mac_accumulator)
  );

  rcif_scale_apply #(.ACC_W(ACC_W), .OUT_W(OUT_W)) u_scale_apply (
    .accumulator_i(mac_accumulator), .scale_q8_8_i(scale_mem[row_q]),
    .bias_i(bias_mem[row_q]), .result_o(scaled_result),
    .saturated_o(scale_saturated)
  );

  rcif_activation_unit #(.DATA_W(OUT_W)) u_activation (
    .mode_i(activation_mode_q), .value_i(scaled_result),
    .value_o(activated_result), .mode_valid_o(activation_mode_valid)
  );

  rcif_accumulator_bank #(.LANES(LANES), .DATA_W(OUT_W)) u_accumulator_bank (
    .clk_i(clk_i), .rst_ni(rst_ni), .clear_i(bank_clear),
    .write_valid_i(bank_write), .write_index_i(row_q),
    .write_data_i(activated_result), .values_o(bank_values)
  );

  rcif_norm_unit #(.LANES(LANES), .DATA_W(OUT_W)) u_norm (
    .clk_i(clk_i), .rst_ni(rst_ni), .req_valid_i(norm_req_valid),
    .req_ready_o(norm_req_ready), .req_values_i(bank_values),
    .req_gain_q8_8_i(norm_gains), .req_epsilon_i(norm_epsilon_q),
    .rsp_valid_o(norm_rsp_valid), .rsp_ready_i(norm_rsp_ready),
    .rsp_values_o(norm_rsp_values), .rsp_saturated_o(norm_rsp_saturated)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      weight_valid_q <= '0;
      activation_q <= '0;
      activation_mode_q <= '0;
      norm_enable_q <= 1'b0;
      norm_epsilon_q <= '0;
      row_q <= '0;
      saturated_q <= '0;
      config_error_q <= 1'b0;
      for (int row = 0; row < LANES; row++) begin
        weight_format_mem[row] <= '0;
        weight_data_mem[row] <= '0;
        zero_point_mem[row] <= '0;
        scale_mem[row] <= '0;
        bias_mem[row] <= '0;
        norm_gain_mem[row] <= OUT_W'(256);
      end
    end else begin
      if (weight_write_valid_i && weight_write_ready_o) begin
        weight_format_mem[weight_write_row_i] <= weight_write_format_i;
        weight_data_mem[weight_write_row_i] <= weight_write_data_i;
        zero_point_mem[weight_write_row_i] <= weight_write_zero_point_i;
        scale_mem[weight_write_row_i] <= weight_write_scale_q8_8_i;
        bias_mem[weight_write_row_i] <= weight_write_bias_i;
        norm_gain_mem[weight_write_row_i] <= weight_write_norm_gain_q8_8_i;
        weight_valid_q[weight_write_row_i] <= 1'b1;
      end
      unique case (state_q)
        IDLE: if (req_valid_i && req_ready_o) begin
          activation_q <= req_activation_i;
          activation_mode_q <= req_activation_mode_i;
          norm_enable_q <= req_norm_enable_i && request_config_valid;
          norm_epsilon_q <= req_norm_epsilon_i;
          row_q <= '0;
          saturated_q <= '0;
          config_error_q <= !request_config_valid;
          state_q <= request_config_valid ? RUN : RESPOND;
        end
        RUN: begin
          if (!weight_format_valid || !activation_mode_valid) config_error_q <= 1'b1;
          if (scale_saturated) saturated_q[row_q] <= 1'b1;
          if (row_q == $clog2(LANES)'(LANES-1)) begin
            state_q <= POST;
          end else begin
            row_q <= row_q + 1'b1;
          end
        end
        POST: begin
          if (!norm_enable_q) state_q <= RESPOND;
          else if (norm_req_valid && norm_req_ready) state_q <= WAIT_NORM;
        end
        WAIT_NORM: if (norm_rsp_valid && rsp_ready_i) state_q <= IDLE;
        RESPOND: if (rsp_ready_i) state_q <= IDLE;
        default: state_q <= IDLE;
      endcase
    end
  end
endmodule
