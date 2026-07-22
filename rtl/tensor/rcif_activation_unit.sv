module rcif_activation_unit #(
  parameter int DATA_W = 16
) (
  input  logic [1:0]                 mode_i,
  input  logic signed [DATA_W-1:0]   value_i,
  output logic signed [DATA_W-1:0]   value_o,
  output logic                       mode_valid_o
);
  localparam logic [1:0] MODE_BYPASS = 2'd0;
  localparam logic [1:0] MODE_RELU = 2'd1;
  localparam logic [1:0] MODE_CLAMP_INT8 = 2'd2;

  always_comb begin
    value_o = value_i;
    mode_valid_o = 1'b1;
    unique case (mode_i)
      MODE_BYPASS: value_o = value_i;
      MODE_RELU: value_o = (value_i < 0) ? '0 : value_i;
      MODE_CLAMP_INT8: begin
        if (value_i > 127) value_o = DATA_W'(127);
        else if (value_i < -128) value_o = -DATA_W'(128);
        else value_o = value_i;
      end
      default: begin
        value_o = '0;
        mode_valid_o = 1'b0;
      end
    endcase
  end
endmodule
