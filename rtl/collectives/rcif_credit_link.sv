/* verilator lint_off SYNCASYNCNET */
module rcif_credit_link #(
  parameter int FLIT_W = 128,
  parameter int CREDIT_DEPTH = 4
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  logic                         flush_i,
  input  logic                         tx_valid_i,
  output logic                         tx_ready_o,
  input  logic [FLIT_W-1:0]            tx_flit_i,
  output logic                         rx_valid_o,
  input  logic                         rx_ready_i,
  output logic [FLIT_W-1:0]            rx_flit_o,
  output logic [$clog2(CREDIT_DEPTH+1)-1:0] credits_o
);
  localparam int PTR_W = (CREDIT_DEPTH <= 1) ? 1 : $clog2(CREDIT_DEPTH);
  localparam int COUNT_W = $clog2(CREDIT_DEPTH+1);

  logic [FLIT_W-1:0] fifo_q [0:CREDIT_DEPTH-1];
  logic [PTR_W-1:0] write_ptr_q, read_ptr_q;
  logic [COUNT_W-1:0] count_q;
  logic push, pop;

  initial begin
    if (CREDIT_DEPTH < 1) $error("CREDIT_DEPTH must be at least one");
  end

  assign tx_ready_o = (count_q != COUNT_W'(CREDIT_DEPTH));
  assign rx_valid_o = (count_q != '0);
  assign rx_flit_o = fifo_q[read_ptr_q];
  assign credits_o = COUNT_W'(CREDIT_DEPTH) - count_q;
  assign push = tx_valid_i && tx_ready_o;
  assign pop = rx_valid_o && rx_ready_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni || flush_i) begin
      write_ptr_q <= '0;
      read_ptr_q <= '0;
      count_q <= '0;
    end else begin
      if (push) begin
        fifo_q[write_ptr_q] <= tx_flit_i;
        write_ptr_q <= (write_ptr_q == PTR_W'(CREDIT_DEPTH-1)) ? '0 : write_ptr_q + 1'b1;
      end
      if (pop)
        read_ptr_q <= (read_ptr_q == PTR_W'(CREDIT_DEPTH-1)) ? '0 : read_ptr_q + 1'b1;
      case ({push, pop})
        2'b10: count_q <= count_q + 1'b1;
        2'b01: count_q <= count_q - 1'b1;
        default: count_q <= count_q;
      endcase
    end
  end

  // Safety half of the credit proof. Liveness under the documented legal
  // assumption (every receiver eventually asserts ready) is exhaustively
  // checked by dv/tests/collectives/test_credit_protocol.py.
  assert property (@(posedge clk_i) disable iff (!rst_ni)
                   count_q <= COUNT_W'(CREDIT_DEPTH));
  assert property (@(posedge clk_i) disable iff (!rst_ni)
                   push |-> count_q < COUNT_W'(CREDIT_DEPTH));
  assert property (@(posedge clk_i) disable iff (!rst_ni)
                   pop |-> count_q != '0);
  assert property (@(posedge clk_i) disable iff (!rst_ni)
                   rx_valid_o && !rx_ready_i |=> $stable(rx_flit_o));
endmodule
