module rcif_qk_dot_array #(
  parameter int ELEM_W = 8,
  parameter int VEC_LEN = 4,
  parameter int ACC_W = 32
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,

  input  logic                          req_valid_i,
  output logic                          req_ready_o,
  input  logic [(ELEM_W*VEC_LEN)-1:0]   req_query_i,
  input  logic [(ELEM_W*VEC_LEN)-1:0]   req_key_i,

  output logic                          rsp_valid_o,
  input  logic                          rsp_ready_i,
  output logic signed [ACC_W-1:0]       rsp_dot_o
);
  localparam int VEC_W = ELEM_W * VEC_LEN;

  logic rsp_valid_q;
  logic signed [ACC_W-1:0] rsp_dot_q;

  function automatic logic signed [ACC_W-1:0] dot_product(
    input logic [VEC_W-1:0] query,
    input logic [VEC_W-1:0] key
  );
    logic signed [ACC_W-1:0] sum;
    logic signed [ELEM_W-1:0] query_element;
    logic signed [ELEM_W-1:0] key_element;
    logic signed [(2*ELEM_W)-1:0] product;
    begin
      sum = '0;
      for (int idx = 0; idx < VEC_LEN; idx++) begin
        query_element = $signed(query[(idx*ELEM_W) +: ELEM_W]);
        key_element = $signed(key[(idx*ELEM_W) +: ELEM_W]);
        product = query_element * key_element;
        sum = sum + ACC_W'(product);
      end
      dot_product = sum;
    end
  endfunction

  assign req_ready_o = !rsp_valid_q || rsp_ready_i;
  assign rsp_valid_o = rsp_valid_q;
  assign rsp_dot_o = rsp_dot_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_valid_q <= 1'b0;
      rsp_dot_q <= '0;
    end else begin
      if (rsp_valid_q && rsp_ready_i) begin
        rsp_valid_q <= 1'b0;
      end
      if (req_valid_i && req_ready_o) begin
        rsp_valid_q <= 1'b1;
        rsp_dot_q <= dot_product(req_query_i, req_key_i);
      end
    end
  end

`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert(ELEM_W > 0);
      assert(VEC_LEN > 0);
      assert(ACC_W >= (2 * ELEM_W));
    end
  end
`endif
endmodule
