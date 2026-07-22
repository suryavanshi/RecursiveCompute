module rcif_v_reduce #(
  parameter int OUT_W = 16,
  parameter int VEC_LEN = 4,
  parameter int ACC_W = 48
) (
  input  logic                        clk_i,
  input  logic                        rst_ni,
  input  logic                        req_valid_i,
  output logic                        req_ready_o,
  input  logic                        req_empty_i,
  input  logic [ACC_W-1:0]            req_denominator_i,
  input  logic [(ACC_W*VEC_LEN)-1:0]  req_accumulator_i,
  output logic                        rsp_valid_o,
  input  logic                        rsp_ready_i,
  output logic                        rsp_empty_o,
  output logic [(OUT_W*VEC_LEN)-1:0]  rsp_context_o
);
  logic rsp_valid_q, rsp_empty_q;
  logic signed [OUT_W-1:0] context_q [0:VEC_LEN-1];

  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic signed [OUT_W-1:0] normalize(
    input logic signed [ACC_W-1:0] accumulator,
    input logic [ACC_W-1:0] denominator
  );
    logic signed [ACC_W:0] numerator_ext;
    logic signed [ACC_W:0] denominator_ext;
    logic signed [ACC_W:0] quotient;
    begin
      numerator_ext = {{1{accumulator[ACC_W-1]}}, accumulator};
      denominator_ext = $signed({1'b0, denominator});
      quotient = numerator_ext / denominator_ext;
      normalize = quotient[OUT_W-1:0];
    end
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  assign req_ready_o = !rsp_valid_q || rsp_ready_i;
  assign rsp_valid_o = rsp_valid_q;
  assign rsp_empty_o = rsp_empty_q;
  for (genvar dim = 0; dim < VEC_LEN; dim++) begin : gen_context_pack
    assign rsp_context_o[(dim*OUT_W) +: OUT_W] = context_q[dim];
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_valid_q <= 1'b0;
      rsp_empty_q <= 1'b1;
      for (int dim = 0; dim < VEC_LEN; dim++) begin
        context_q[dim] <= '0;
      end
    end else begin
      if (rsp_valid_q && rsp_ready_i) begin
        rsp_valid_q <= 1'b0;
      end
      if (req_valid_i && req_ready_o) begin
        rsp_valid_q <= 1'b1;
        rsp_empty_q <= req_empty_i;
        for (int dim = 0; dim < VEC_LEN; dim++) begin
          if (req_empty_i || (req_denominator_i == 0)) begin
            context_q[dim] <= '0;
          end else begin
            context_q[dim] <= normalize(
              $signed(req_accumulator_i[(dim*ACC_W) +: ACC_W]), req_denominator_i);
          end
        end
      end
    end
  end
endmodule
