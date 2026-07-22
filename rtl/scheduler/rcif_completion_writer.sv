module rcif_completion_writer #(
  parameter int REQ_ID_W = 32,
  parameter int STATUS_W = 32,
  parameter int DATA_W = 64,
  parameter int DEPTH = 4,
  parameter int PTR_W = $clog2(DEPTH)
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  input  logic                  push_valid_i,
  output logic                  push_ready_o,
  input  logic [REQ_ID_W-1:0]   push_request_id_i,
  input  logic [STATUS_W-1:0]   push_status_i,
  input  logic [DATA_W-1:0]     push_result_i,
  output logic                  cpl_valid_o,
  input  logic                  cpl_ready_i,
  output logic [REQ_ID_W-1:0]   cpl_request_id_o,
  output logic [STATUS_W-1:0]   cpl_status_o,
  output logic [DATA_W-1:0]     cpl_result_o
);
  logic [REQ_ID_W-1:0] request_mem [0:DEPTH-1];
  logic [STATUS_W-1:0] status_mem [0:DEPTH-1];
  logic [DATA_W-1:0] result_mem [0:DEPTH-1];
  logic [PTR_W-1:0] read_ptr_q, write_ptr_q;
  logic [PTR_W:0] count_q;

  wire push = push_valid_i && push_ready_o;
  wire pop = cpl_valid_o && cpl_ready_i;

  assign push_ready_o = count_q < (PTR_W+1)'(DEPTH);
  assign cpl_valid_o = count_q != 0;
  assign cpl_request_id_o = request_mem[read_ptr_q];
  assign cpl_status_o = status_mem[read_ptr_q];
  assign cpl_result_o = result_mem[read_ptr_q];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      read_ptr_q <= '0;
      write_ptr_q <= '0;
      count_q <= '0;
    end else begin
      if (push) begin
        request_mem[write_ptr_q] <= push_request_id_i;
        status_mem[write_ptr_q] <= push_status_i;
        result_mem[write_ptr_q] <= push_result_i;
        write_ptr_q <= (write_ptr_q == PTR_W'(DEPTH-1)) ? '0 : write_ptr_q + 1'b1;
      end
      if (pop) begin
        read_ptr_q <= (read_ptr_q == PTR_W'(DEPTH-1)) ? '0 : read_ptr_q + 1'b1;
      end
      unique case ({push, pop})
        2'b10: count_q <= count_q + 1'b1;
        2'b01: count_q <= count_q - 1'b1;
        default: count_q <= count_q;
      endcase
    end
  end
endmodule
