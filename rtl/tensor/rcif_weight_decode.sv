module rcif_weight_decode #(
  parameter int LANES = 4
) (
  input  logic [1:0]             format_i,
  input  logic [31:0]            packed_weight_i,
  input  logic signed [7:0]      zero_point_i,
  output logic signed [(9*LANES)-1:0] decoded_weight_o,
  output logic                   format_valid_o
);
  localparam logic [1:0] FORMAT_INT8 = 2'd0;
  localparam logic [1:0] FORMAT_INT4 = 2'd1;

  always_comb begin
    decoded_weight_o = '0;
    format_valid_o = 1'b1;
    for (int lane = 0; lane < LANES; lane++) begin
      unique case (format_i)
        FORMAT_INT8: decoded_weight_o[(lane*9) +: 9] =
          $signed({packed_weight_i[(lane*8)+7], packed_weight_i[(lane*8) +: 8]}) -
          $signed({zero_point_i[7], zero_point_i});
        FORMAT_INT4: decoded_weight_o[(lane*9) +: 9] =
          $signed({{5{packed_weight_i[(lane*4)+3]}}, packed_weight_i[(lane*4) +: 4]}) -
          $signed({zero_point_i[7], zero_point_i});
        default: begin
          decoded_weight_o[(lane*9) +: 9] = '0;
          format_valid_o = 1'b0;
        end
      endcase
    end
  end
endmodule
