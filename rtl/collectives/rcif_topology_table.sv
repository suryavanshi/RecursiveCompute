module rcif_topology_table #(
  parameter int NUM_NODES = 4,
  parameter int PARTITION_W = 8
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  logic                         cfg_valid_i,
  input  logic [$clog2(NUM_NODES)-1:0] cfg_node_i,
  input  logic                         cfg_active_i,
  input  logic [PARTITION_W-1:0]       cfg_partition_i,
  input  logic [$clog2(NUM_NODES)-1:0] cfg_ring_next_i,
  input  logic [$clog2(NUM_NODES)-1:0] cfg_tree_parent_i,
  input  logic                         route_cfg_valid_i,
  input  logic [$clog2(NUM_NODES)-1:0] route_cfg_node_i,
  input  logic [$clog2(NUM_NODES)-1:0] route_cfg_destination_i,
  input  logic [$clog2(NUM_NODES)-1:0] route_cfg_next_hop_i,
  input  logic                         route_cfg_link_enable_i,
  input  logic [$clog2(NUM_NODES)-1:0] query_node_i,
  input  logic [$clog2(NUM_NODES)-1:0] query_destination_i,
  output logic                         query_active_o,
  output logic [PARTITION_W-1:0]       query_partition_o,
  output logic [$clog2(NUM_NODES)-1:0] query_ring_next_o,
  output logic [$clog2(NUM_NODES)-1:0] query_tree_parent_o,
  output logic [$clog2(NUM_NODES)-1:0] query_next_hop_o,
  output logic                         query_link_enable_o,
  output logic [NUM_NODES-1:0]         active_o,
  output logic [(NUM_NODES*PARTITION_W)-1:0] partitions_o,
  output logic [(NUM_NODES*$clog2(NUM_NODES))-1:0] ring_next_o,
  output logic [(NUM_NODES*$clog2(NUM_NODES))-1:0] tree_parent_o,
  output logic [(NUM_NODES*NUM_NODES*$clog2(NUM_NODES))-1:0] routes_o,
  output logic [(NUM_NODES*NUM_NODES)-1:0] links_enabled_o
);
  localparam int NODE_W = $clog2(NUM_NODES);
  logic [NUM_NODES-1:0] active_q;
  logic [PARTITION_W-1:0] partition_q [0:NUM_NODES-1];
  logic [NODE_W-1:0] ring_next_q [0:NUM_NODES-1];
  logic [NODE_W-1:0] tree_parent_q [0:NUM_NODES-1];
  logic [NODE_W-1:0] next_hop_q [0:NUM_NODES-1][0:NUM_NODES-1];
  logic link_enable_q [0:NUM_NODES-1][0:NUM_NODES-1];

  assign query_active_o = active_q[query_node_i];
  assign query_partition_o = partition_q[query_node_i];
  assign query_ring_next_o = ring_next_q[query_node_i];
  assign query_tree_parent_o = tree_parent_q[query_node_i];
  assign query_next_hop_o = next_hop_q[query_node_i][query_destination_i];
  assign query_link_enable_o = link_enable_q[query_node_i][query_next_hop_o];

  always_comb begin
    active_o = active_q;
    partitions_o = '0;
    ring_next_o = '0;
    tree_parent_o = '0;
    routes_o = '0;
    links_enabled_o = '0;
    for (int node = 0; node < NUM_NODES; node++) begin
      partitions_o[(node*PARTITION_W) +: PARTITION_W] = partition_q[node];
      ring_next_o[(node*NODE_W) +: NODE_W] = ring_next_q[node];
      tree_parent_o[(node*NODE_W) +: NODE_W] = tree_parent_q[node];
      for (int destination = 0; destination < NUM_NODES; destination++) begin
        routes_o[((node*NUM_NODES+destination)*NODE_W) +: NODE_W] =
          next_hop_q[node][destination];
        links_enabled_o[node*NUM_NODES+destination] = link_enable_q[node][destination];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      active_q <= '0;
      for (int node = 0; node < NUM_NODES; node++) begin
        partition_q[node] <= '0;
        ring_next_q[node] <= NODE_W'(node);
        tree_parent_q[node] <= NODE_W'(node);
        for (int destination = 0; destination < NUM_NODES; destination++) begin
          next_hop_q[node][destination] <= NODE_W'(destination);
          link_enable_q[node][destination] <= 1'b0;
        end
      end
    end else begin
      if (cfg_valid_i) begin
        active_q[cfg_node_i] <= cfg_active_i;
        partition_q[cfg_node_i] <= cfg_partition_i;
        ring_next_q[cfg_node_i] <= cfg_ring_next_i;
        tree_parent_q[cfg_node_i] <= cfg_tree_parent_i;
      end
      if (route_cfg_valid_i) begin
        next_hop_q[route_cfg_node_i][route_cfg_destination_i] <= route_cfg_next_hop_i;
        link_enable_q[route_cfg_node_i][route_cfg_next_hop_i] <= route_cfg_link_enable_i;
      end
    end
  end
endmodule
