module rcif_replay_trace #(
  parameter int DEPTH = 64,
  parameter int EVENT_W = 128,
  parameter int PTR_W = $clog2(DEPTH)
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  input  logic                  clear_i,
  input  logic                  event_valid_i,
  input  logic [EVENT_W-1:0]    event_i,
  input  logic [PTR_W-1:0]      read_index_i,
  output logic [EVENT_W-1:0]    read_event_o,
  output logic [PTR_W:0]        event_count_o,
  output logic                  overflow_o
);
  logic [EVENT_W-1:0] event_mem [0:DEPTH-1];
  logic [PTR_W:0] count_q;
  logic overflow_q;

  assign read_event_o = event_mem[read_index_i];
  assign event_count_o = count_q;
  assign overflow_o = overflow_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count_q <= '0;
      overflow_q <= 1'b0;
    end else if (clear_i) begin
      count_q <= '0;
      overflow_q <= 1'b0;
    end else if (event_valid_i) begin
      if (count_q < (PTR_W+1)'(DEPTH)) begin
        event_mem[count_q[PTR_W-1:0]] <= event_i;
        count_q <= count_q + 1'b1;
      end else begin
        overflow_q <= 1'b1;
      end
    end
  end
endmodule
