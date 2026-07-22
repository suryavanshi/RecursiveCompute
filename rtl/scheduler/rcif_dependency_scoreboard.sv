module rcif_dependency_scoreboard #(
  parameter int MAX_NODES = 8,
  parameter int NODE_ID_W = $clog2(MAX_NODES)
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    clear_i,
  input  logic                    complete_valid_i,
  input  logic [NODE_ID_W-1:0]    complete_node_id_i,
  input  logic [MAX_NODES-1:0]    dependency_mask_i,
  output logic                    dependencies_ready_o,
  output logic [MAX_NODES-1:0]    completed_mask_o
);
  logic [MAX_NODES-1:0] completed_q;

  assign completed_mask_o = completed_q;
  assign dependencies_ready_o = (dependency_mask_i & ~completed_q) == '0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      completed_q <= '0;
    end else if (clear_i) begin
      completed_q <= '0;
    end else if (complete_valid_i) begin
      completed_q[complete_node_id_i] <= 1'b1;
    end
  end
endmodule
