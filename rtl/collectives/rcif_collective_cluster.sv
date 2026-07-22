/* verilator lint_off SYNCASYNCNET */
module rcif_collective_cluster #(
  parameter int NUM_NODES = 4,
  parameter int DATA_W = 32,
  parameter int FLIT_W = 128,
  parameter int CREDIT_DEPTH = 2
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  logic                         cmd_valid_i,
  output logic                         cmd_ready_o,
  input  logic [7:0]                   cmd_collective_id_i,
  input  logic [(NUM_NODES*DATA_W)-1:0] cmd_local_values_i,
  input  logic [NUM_NODES-1:0]         link_stall_i,
  output logic                         done_o,
  output logic                         protocol_error_o,
  output logic [(NUM_NODES*DATA_W)-1:0] results_o,
  output logic [(NUM_NODES*$clog2(CREDIT_DEPTH+1))-1:0] credits_o
);
  localparam int CREDIT_W = $clog2(CREDIT_DEPTH+1);

  logic [NUM_NODES-1:0] node_idle, node_result_valid, node_error;
  logic [DATA_W-1:0] node_result [0:NUM_NODES-1];
  logic [NUM_NODES-1:0] node_tx_valid, node_tx_ready;
  logic [FLIT_W-1:0] node_tx_flit [0:NUM_NODES-1];
  logic [NUM_NODES-1:0] node_rx_valid, node_rx_ready;
  logic [FLIT_W-1:0] node_rx_flit [0:NUM_NODES-1];
  logic [NUM_NODES-1:0] link_rx_valid, link_rx_ready;
  logic [FLIT_W-1:0] link_rx_flit [0:NUM_NODES-1];
  logic [CREDIT_W-1:0] link_credits [0:NUM_NODES-1];
  logic accept_command;

  assign accept_command = cmd_valid_i && cmd_ready_o;
  assign protocol_error_o = |node_error;

  always_comb begin
    results_o = '0;
    credits_o = '0;
    for (int node = 0; node < NUM_NODES; node++) begin
      results_o[(node*DATA_W) +: DATA_W] = node_result[node];
      credits_o[(node*CREDIT_W) +: CREDIT_W] = link_credits[node];
    end
  end

  generate
    for (genvar node = 0; node < NUM_NODES; node++) begin : g_nodes
      localparam int NEXT_NODE = (node + 1) % NUM_NODES;

      rcif_ring_collective_node #(
        .NODE_ID(node), .NUM_NODES(NUM_NODES), .DATA_W(DATA_W), .FLIT_W(FLIT_W)
      ) u_node (
        .clk_i(clk_i), .rst_ni(rst_ni), .init_i(accept_command),
        .start_i(accept_command && (node == 0)),
        .collective_id_i(cmd_collective_id_i),
        .local_value_i(cmd_local_values_i[(node*DATA_W) +: DATA_W]),
        .tx_valid_o(node_tx_valid[node]), .tx_ready_i(node_tx_ready[node]),
        .tx_flit_o(node_tx_flit[node]), .rx_valid_i(node_rx_valid[node]),
        .rx_ready_o(node_rx_ready[node]), .rx_flit_i(node_rx_flit[node]),
        .idle_o(node_idle[node]), .result_valid_o(node_result_valid[node]),
        .result_o(node_result[node]), .protocol_error_o(node_error[node])
      );

      rcif_credit_link #(.FLIT_W(FLIT_W), .CREDIT_DEPTH(CREDIT_DEPTH)) u_link (
        .clk_i(clk_i), .rst_ni(rst_ni), .flush_i(1'b0),
        .tx_valid_i(node_tx_valid[node]), .tx_ready_o(node_tx_ready[node]),
        .tx_flit_i(node_tx_flit[node]), .rx_valid_o(link_rx_valid[node]),
        .rx_ready_i(link_rx_ready[node]), .rx_flit_o(link_rx_flit[node]),
        .credits_o(link_credits[node])
      );

      assign node_rx_valid[NEXT_NODE] = link_rx_valid[node] && !link_stall_i[node];
      assign node_rx_flit[NEXT_NODE] = link_rx_flit[node];
      assign link_rx_ready[node] = node_rx_ready[NEXT_NODE] && !link_stall_i[node];
    end
  endgenerate

  // The command may only start with every physical link fully credited.
  always_comb begin
    cmd_ready_o = &node_idle;
    for (int link = 0; link < NUM_NODES; link++)
      cmd_ready_o &= (link_credits[link] == CREDIT_W'(CREDIT_DEPTH));
  end

  assign done_o = (&node_result_valid) && cmd_ready_o;

  assert property (@(posedge clk_i) disable iff (!rst_ni)
                   done_o |-> !protocol_error_o);
endmodule
