/* verilator lint_off MULTIDRIVEN */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off SYNCASYNCNET */
/* verilator lint_off UNUSEDSIGNAL */
module rcif_collective_engine #(
  parameter int NUM_NODES = 4,
  parameter int DATA_W = 32,
  parameter int PARTITION_W = 8,
  parameter int COLLECTIVE_ID_W = 8,
  parameter int MAX_HOPS = NUM_NODES,
  parameter int CREDIT_DEPTH = 2
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,

  input  logic                         topo_cfg_valid_i,
  input  logic [$clog2(NUM_NODES)-1:0] topo_cfg_node_i,
  input  logic                         topo_cfg_active_i,
  input  logic [PARTITION_W-1:0]       topo_cfg_partition_i,
  input  logic [$clog2(NUM_NODES)-1:0] topo_cfg_ring_next_i,
  input  logic [$clog2(NUM_NODES)-1:0] topo_cfg_tree_parent_i,
  input  logic                         route_cfg_valid_i,
  input  logic [$clog2(NUM_NODES)-1:0] route_cfg_node_i,
  input  logic [$clog2(NUM_NODES)-1:0] route_cfg_destination_i,
  input  logic [$clog2(NUM_NODES)-1:0] route_cfg_next_hop_i,
  input  logic                         route_cfg_link_enable_i,

  input  logic                         fault_cfg_valid_i,
  input  logic                         fault_cfg_clear_i,
  input  logic [$clog2(NUM_NODES)-1:0] fault_cfg_source_i,
  input  logic [$clog2(NUM_NODES)-1:0] fault_cfg_destination_i,
  input  logic                         fault_cfg_persistent_i,

  input  logic                         cmd_valid_i,
  output logic                         cmd_ready_o,
  input  logic [2:0]                   cmd_opcode_i,
  input  logic [COLLECTIVE_ID_W-1:0]   cmd_collective_id_i,
  input  logic [PARTITION_W-1:0]       cmd_partition_i,
  input  logic [NUM_NODES-1:0]         cmd_participants_i,
  input  logic [$clog2(NUM_NODES)-1:0] cmd_root_i,
  input  logic [7:0]                   cmd_retry_limit_i,
  input  logic [(NUM_NODES*DATA_W)-1:0] cmd_local_values_i,
  input  logic [(NUM_NODES*NUM_NODES*DATA_W)-1:0] cmd_alltoall_values_i,

  output logic                         rsp_valid_o,
  input  logic                         rsp_ready_i,
  output logic [COLLECTIVE_ID_W-1:0]   rsp_collective_id_o,
  output logic [7:0]                   rsp_status_o,
  output logic [15:0]                  rsp_retry_count_o,
  output logic [$clog2(NUM_NODES)-1:0] rsp_fault_source_o,
  output logic [$clog2(NUM_NODES)-1:0] rsp_fault_destination_o,
  output logic                         rsp_committed_o,
  output logic [(NUM_NODES*DATA_W)-1:0] rsp_local_values_o,
  output logic [(NUM_NODES*NUM_NODES*DATA_W)-1:0] rsp_alltoall_values_o
);
  import rcif_collective_protocol_pkg::*;

  localparam int NODE_W = $clog2(NUM_NODES);
  localparam int PAIR_W = $clog2(NUM_NODES*NUM_NODES+1);

  initial begin
    if (NUM_NODES < 2) $error("NUM_NODES must be at least two");
    if (CREDIT_DEPTH < 1) $error("CREDIT_DEPTH must be at least one");
  end

  typedef enum logic [3:0] {
    IDLE,
    RING_REDUCE,
    RING_BROADCAST,
    TREE_REDUCE,
    TREE_BROADCAST,
    A2A_SELECT,
    A2A_ROUTE
  } state_t;

  state_t state_q;
  logic [NUM_NODES-1:0] topo_active;
  logic [(NUM_NODES*PARTITION_W)-1:0] topo_partitions;
  logic [(NUM_NODES*NODE_W)-1:0] topo_ring_next;
  logic [(NUM_NODES*NODE_W)-1:0] topo_tree_parent;
  logic [(NUM_NODES*NUM_NODES*NODE_W)-1:0] topo_routes;
  logic [(NUM_NODES*NUM_NODES)-1:0] topo_links;
  logic topo_query_active, topo_query_link_enable;
  logic [PARTITION_W-1:0] topo_query_partition;
  logic [NODE_W-1:0] topo_query_ring_next, topo_query_tree_parent;
  logic [NODE_W-1:0] topo_query_next_hop;

  logic [2:0] opcode_q;
  logic [COLLECTIVE_ID_W-1:0] collective_id_q;
  logic [PARTITION_W-1:0] partition_q;
  logic [NUM_NODES-1:0] participants_q;
  logic [NODE_W-1:0] root_q, first_q, current_q;
  logic [7:0] retry_limit_q, edge_retry_q, hop_count_q;
  logic [15:0] retry_count_q;
  logic [DATA_W-1:0] reduction_q;
  logic [NUM_NODES-1:0] visited_q, processed_q, broadcast_q;
  logic [DATA_W-1:0] tree_accum_q [0:NUM_NODES-1];
  logic [(NUM_NODES*NUM_NODES*DATA_W)-1:0] alltoall_input_q;
  logic [PAIR_W-1:0] pair_index_q;
  logic [NODE_W-1:0] pair_source_q, pair_destination_q;

  logic fault_armed_q, fault_persistent_q;
  logic [NODE_W-1:0] fault_source_q, fault_destination_q;

  logic rsp_valid_q;
  logic [COLLECTIVE_ID_W-1:0] rsp_collective_id_q;
  logic [7:0] rsp_status_q;
  logic [15:0] rsp_retry_count_q;
  logic [NODE_W-1:0] rsp_fault_source_q, rsp_fault_destination_q;
  logic rsp_committed_q;
  logic [(NUM_NODES*DATA_W)-1:0] rsp_local_values_q;
  logic [(NUM_NODES*NUM_NODES*DATA_W)-1:0] rsp_alltoall_values_q;

  logic [NODE_W-1:0] tree_candidate;
  logic tree_candidate_valid;
  logic [NODE_W-1:0] broadcast_candidate;
  logic broadcast_candidate_valid;
  logic [NODE_W-1:0] hop_destination;
  logic hop_link_enabled, hop_partition_valid, hop_faulted;

  function automatic logic [NODE_W-1:0] ring_next(input logic [NODE_W-1:0] node);
    return topo_ring_next[(node*NODE_W) +: NODE_W];
  endfunction

  function automatic logic [NODE_W-1:0] tree_parent(input logic [NODE_W-1:0] node);
    return topo_tree_parent[(node*NODE_W) +: NODE_W];
  endfunction

  function automatic logic [NODE_W-1:0] route_next(
    input logic [NODE_W-1:0] node,
    input logic [NODE_W-1:0] destination
  );
    return topo_routes[((node*NUM_NODES+destination)*NODE_W) +: NODE_W];
  endfunction

  function automatic logic [PARTITION_W-1:0] node_partition(input logic [NODE_W-1:0] node);
    return topo_partitions[(node*PARTITION_W) +: PARTITION_W];
  endfunction

  rcif_topology_table #(.NUM_NODES(NUM_NODES), .PARTITION_W(PARTITION_W)) u_topology (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .cfg_valid_i(topo_cfg_valid_i), .cfg_node_i(topo_cfg_node_i),
    .cfg_active_i(topo_cfg_active_i), .cfg_partition_i(topo_cfg_partition_i),
    .cfg_ring_next_i(topo_cfg_ring_next_i),
    .cfg_tree_parent_i(topo_cfg_tree_parent_i),
    .route_cfg_valid_i(route_cfg_valid_i), .route_cfg_node_i(route_cfg_node_i),
    .route_cfg_destination_i(route_cfg_destination_i),
    .route_cfg_next_hop_i(route_cfg_next_hop_i),
    .route_cfg_link_enable_i(route_cfg_link_enable_i),
    .query_node_i('0), .query_destination_i('0),
    .query_active_o(topo_query_active), .query_partition_o(topo_query_partition),
    .query_ring_next_o(topo_query_ring_next),
    .query_tree_parent_o(topo_query_tree_parent),
    .query_next_hop_o(topo_query_next_hop),
    .query_link_enable_o(topo_query_link_enable),
    .active_o(topo_active), .partitions_o(topo_partitions),
    .ring_next_o(topo_ring_next), .tree_parent_o(topo_tree_parent),
    .routes_o(topo_routes), .links_enabled_o(topo_links)
  );

  always_comb begin
    tree_candidate = '0;
    tree_candidate_valid = 1'b0;
    for (int node = NUM_NODES-1; node >= 0; node--) begin
      logic has_unprocessed_child;
      has_unprocessed_child = 1'b0;
      for (int child = 0; child < NUM_NODES; child++) begin
        if (participants_q[child] && !processed_q[child] &&
            (tree_parent(NODE_W'(child)) == NODE_W'(node)) && (child != node))
          has_unprocessed_child = 1'b1;
      end
      if (participants_q[node] && !processed_q[node] && !has_unprocessed_child) begin
        tree_candidate = NODE_W'(node);
        tree_candidate_valid = 1'b1;
      end
    end

    broadcast_candidate = '0;
    broadcast_candidate_valid = 1'b0;
    for (int node = NUM_NODES-1; node >= 0; node--) begin
      if (participants_q[node] && !broadcast_q[node] &&
          broadcast_q[tree_parent(NODE_W'(node))]) begin
        broadcast_candidate = NODE_W'(node);
        broadcast_candidate_valid = 1'b1;
      end
    end

    case (state_q)
      RING_REDUCE, RING_BROADCAST: hop_destination = ring_next(current_q);
      TREE_REDUCE: hop_destination = tree_parent(tree_candidate);
      TREE_BROADCAST: hop_destination = broadcast_candidate;
      A2A_ROUTE: hop_destination = route_next(current_q, pair_destination_q);
      default: hop_destination = current_q;
    endcase
    hop_link_enabled = topo_links[current_q*NUM_NODES+hop_destination];
    hop_partition_valid = topo_active[current_q] && topo_active[hop_destination] &&
                          (node_partition(current_q) == partition_q) &&
                          (node_partition(hop_destination) == partition_q) &&
                          participants_q[current_q] && participants_q[hop_destination];
    hop_faulted = fault_armed_q && (current_q == fault_source_q) &&
                  (hop_destination == fault_destination_q);
  end

  assign cmd_ready_o = (state_q == IDLE) && !rsp_valid_q;
  assign rsp_valid_o = rsp_valid_q;
  assign rsp_collective_id_o = rsp_collective_id_q;
  assign rsp_status_o = rsp_status_q;
  assign rsp_retry_count_o = rsp_retry_count_q;
  assign rsp_fault_source_o = rsp_fault_source_q;
  assign rsp_fault_destination_o = rsp_fault_destination_q;
  assign rsp_committed_o = rsp_committed_q;
  assign rsp_local_values_o = rsp_local_values_q;
  assign rsp_alltoall_values_o = rsp_alltoall_values_q;

  task automatic fail_operation(
    input logic [7:0] status,
    input logic [NODE_W-1:0] source,
    input logic [NODE_W-1:0] destination
  );
    begin
      rsp_valid_q <= 1'b1;
      rsp_collective_id_q <= collective_id_q;
      rsp_status_q <= status;
      rsp_retry_count_q <= retry_count_q;
      rsp_fault_source_q <= source;
      rsp_fault_destination_q <= destination;
      rsp_committed_q <= 1'b0;
      rsp_local_values_q <= '0;
      rsp_alltoall_values_q <= '0;
      state_q <= IDLE;
    end
  endtask

  task automatic complete_operation;
    begin
      rsp_valid_q <= 1'b1;
      rsp_collective_id_q <= collective_id_q;
      rsp_status_q <= RCIF_COLL_STATUS_OK;
      rsp_retry_count_q <= retry_count_q;
      rsp_fault_source_q <= '0;
      rsp_fault_destination_q <= '0;
      rsp_committed_q <= 1'b1;
      state_q <= IDLE;
    end
  endtask

  task automatic retry_or_fail(
    input logic [NODE_W-1:0] source,
    input logic [NODE_W-1:0] destination
  );
    begin
      if (edge_retry_q < retry_limit_q) begin
        edge_retry_q <= edge_retry_q + 1'b1;
        retry_count_q <= retry_count_q + 1'b1;
        if (!fault_persistent_q) fault_armed_q <= 1'b0;
      end else begin
        fail_operation(RCIF_COLL_STATUS_RETRY_EXHAUSTED, source, destination);
      end
    end
  endtask

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      opcode_q <= '0;
      collective_id_q <= '0;
      partition_q <= '0;
      participants_q <= '0;
      root_q <= '0;
      first_q <= '0;
      current_q <= '0;
      retry_limit_q <= '0;
      edge_retry_q <= '0;
      hop_count_q <= '0;
      retry_count_q <= '0;
      reduction_q <= '0;
      visited_q <= '0;
      processed_q <= '0;
      broadcast_q <= '0;
      alltoall_input_q <= '0;
      pair_index_q <= '0;
      pair_source_q <= '0;
      pair_destination_q <= '0;
      fault_armed_q <= 1'b0;
      fault_persistent_q <= 1'b0;
      fault_source_q <= '0;
      fault_destination_q <= '0;
      rsp_valid_q <= 1'b0;
      rsp_collective_id_q <= '0;
      rsp_status_q <= '0;
      rsp_retry_count_q <= '0;
      rsp_fault_source_q <= '0;
      rsp_fault_destination_q <= '0;
      rsp_committed_q <= 1'b0;
      rsp_local_values_q <= '0;
      rsp_alltoall_values_q <= '0;
      for (int node = 0; node < NUM_NODES; node++) tree_accum_q[node] <= '0;
    end else begin
      if (rsp_valid_q && rsp_ready_i) rsp_valid_q <= 1'b0;

      if (fault_cfg_clear_i) fault_armed_q <= 1'b0;
      if (fault_cfg_valid_i) begin
        fault_armed_q <= 1'b1;
        fault_source_q <= fault_cfg_source_i;
        fault_destination_q <= fault_cfg_destination_i;
        fault_persistent_q <= fault_cfg_persistent_i;
      end

      if (cmd_valid_i && cmd_ready_o) begin
        opcode_q <= cmd_opcode_i;
        collective_id_q <= cmd_collective_id_i;
        partition_q <= cmd_partition_i;
        participants_q <= cmd_participants_i;
        root_q <= cmd_root_i;
        retry_limit_q <= cmd_retry_limit_i;
        edge_retry_q <= '0;
        retry_count_q <= '0;
        visited_q <= '0;
        processed_q <= '0;
        broadcast_q <= '0;
        alltoall_input_q <= cmd_alltoall_values_i;
        pair_index_q <= '0;
        rsp_local_values_q <= '0;
        rsp_alltoall_values_q <= '0;
        rsp_committed_q <= 1'b0;
        for (int node = 0; node < NUM_NODES; node++)
          tree_accum_q[node] <= cmd_local_values_i[(node*DATA_W) +: DATA_W];

        if ((cmd_participants_i == '0) ||
            ((cmd_participants_i & ~topo_active) != '0) ||
            !cmd_participants_i[cmd_root_i]) begin
          rsp_valid_q <= 1'b1;
          rsp_collective_id_q <= cmd_collective_id_i;
          rsp_status_q <= RCIF_COLL_STATUS_BAD_COMMAND;
          rsp_retry_count_q <= '0;
          rsp_fault_source_q <= '0;
          rsp_fault_destination_q <= '0;
          rsp_committed_q <= 1'b0;
          state_q <= IDLE;
        end else begin
          logic partition_mismatch;
          partition_mismatch = 1'b0;
          for (int node = 0; node < NUM_NODES; node++) begin
            if (cmd_participants_i[node] &&
                (node_partition(NODE_W'(node)) != cmd_partition_i))
              partition_mismatch = 1'b1;
          end
          if (partition_mismatch) begin
            rsp_valid_q <= 1'b1;
            rsp_collective_id_q <= cmd_collective_id_i;
            rsp_status_q <= RCIF_COLL_STATUS_PARTITION;
            rsp_retry_count_q <= '0;
            rsp_fault_source_q <= '0;
            rsp_fault_destination_q <= '0;
            rsp_committed_q <= 1'b0;
            state_q <= IDLE;
          end else begin
            first_q <= cmd_root_i;
            current_q <= cmd_root_i;
            reduction_q <= cmd_local_values_i[(cmd_root_i*DATA_W) +: DATA_W];
            visited_q[cmd_root_i] <= 1'b1;
            processed_q <= '0;
            broadcast_q <= '0;
            case (cmd_opcode_i)
              RCIF_COLL_OP_RING_ALLREDUCE: state_q <= RING_REDUCE;
              RCIF_COLL_OP_TREE_ALLREDUCE: state_q <= TREE_REDUCE;
              RCIF_COLL_OP_ALLTOALL: state_q <= A2A_SELECT;
              default: begin
                rsp_valid_q <= 1'b1;
                rsp_collective_id_q <= cmd_collective_id_i;
                rsp_status_q <= RCIF_COLL_STATUS_BAD_COMMAND;
                rsp_retry_count_q <= '0;
                rsp_committed_q <= 1'b0;
                state_q <= IDLE;
              end
            endcase
          end
        end
      end else begin
        case (state_q)
          RING_REDUCE: begin
            if (!hop_partition_valid) begin
              fail_operation(RCIF_COLL_STATUS_PARTITION, current_q, hop_destination);
            end else if (!hop_link_enabled) begin
              fail_operation(RCIF_COLL_STATUS_TOPOLOGY, current_q, hop_destination);
            end else if (hop_faulted) begin
              retry_or_fail(current_q, hop_destination);
            end else begin
              edge_retry_q <= '0;
              current_q <= hop_destination;
              if (hop_destination == first_q) begin
                if (visited_q == participants_q) begin
                  rsp_local_values_q[(first_q*DATA_W) +: DATA_W] <= reduction_q;
                  broadcast_q <= '0;
                  broadcast_q[first_q] <= 1'b1;
                  state_q <= RING_BROADCAST;
                end else begin
                  fail_operation(RCIF_COLL_STATUS_TOPOLOGY, current_q, hop_destination);
                end
              end else if (visited_q[hop_destination]) begin
                fail_operation(RCIF_COLL_STATUS_TOPOLOGY, current_q, hop_destination);
              end else begin
                reduction_q <= reduction_q + tree_accum_q[hop_destination];
                visited_q[hop_destination] <= 1'b1;
              end
            end
          end

          RING_BROADCAST: begin
            if (!hop_partition_valid) begin
              fail_operation(RCIF_COLL_STATUS_PARTITION, current_q, hop_destination);
            end else if (!hop_link_enabled) begin
              fail_operation(RCIF_COLL_STATUS_TOPOLOGY, current_q, hop_destination);
            end else if (hop_faulted) begin
              retry_or_fail(current_q, hop_destination);
            end else begin
              edge_retry_q <= '0;
              current_q <= hop_destination;
              if (hop_destination == first_q) begin
                if (broadcast_q == participants_q) complete_operation();
                else fail_operation(RCIF_COLL_STATUS_TOPOLOGY, current_q, hop_destination);
              end else if (broadcast_q[hop_destination]) begin
                fail_operation(RCIF_COLL_STATUS_TOPOLOGY, current_q, hop_destination);
              end else begin
                broadcast_q[hop_destination] <= 1'b1;
                rsp_local_values_q[(hop_destination*DATA_W) +: DATA_W] <= reduction_q;
              end
            end
          end

          TREE_REDUCE: begin
            if (!tree_candidate_valid) begin
              fail_operation(RCIF_COLL_STATUS_TOPOLOGY, root_q, root_q);
            end else if (tree_candidate == root_q) begin
              if ((processed_q | (NUM_NODES'(1) << root_q)) == participants_q) begin
                rsp_local_values_q[(root_q*DATA_W) +: DATA_W] <= tree_accum_q[root_q];
                broadcast_q <= '0;
                broadcast_q[root_q] <= 1'b1;
                current_q <= root_q;
                state_q <= TREE_BROADCAST;
              end else begin
                fail_operation(RCIF_COLL_STATUS_TOPOLOGY, root_q, root_q);
              end
            end else begin
              current_q <= tree_candidate;
              if (!topo_links[tree_candidate*NUM_NODES+tree_parent(tree_candidate)]) begin
                fail_operation(RCIF_COLL_STATUS_TOPOLOGY,
                               tree_candidate, tree_parent(tree_candidate));
              end else if ((node_partition(tree_candidate) != partition_q) ||
                           (node_partition(tree_parent(tree_candidate)) != partition_q) ||
                           !participants_q[tree_parent(tree_candidate)]) begin
                fail_operation(RCIF_COLL_STATUS_PARTITION,
                               tree_candidate, tree_parent(tree_candidate));
              end else if (fault_armed_q && (tree_candidate == fault_source_q) &&
                           (tree_parent(tree_candidate) == fault_destination_q)) begin
                retry_or_fail(tree_candidate, tree_parent(tree_candidate));
              end else begin
                edge_retry_q <= '0;
                tree_accum_q[tree_parent(tree_candidate)] <=
                  tree_accum_q[tree_parent(tree_candidate)] + tree_accum_q[tree_candidate];
                processed_q[tree_candidate] <= 1'b1;
              end
            end
          end

          TREE_BROADCAST: begin
            if (broadcast_q == participants_q) begin
              complete_operation();
            end else if (!broadcast_candidate_valid) begin
              fail_operation(RCIF_COLL_STATUS_TOPOLOGY, root_q, root_q);
            end else begin
              current_q <= tree_parent(broadcast_candidate);
              if (!topo_links[tree_parent(broadcast_candidate)*NUM_NODES+broadcast_candidate]) begin
                fail_operation(RCIF_COLL_STATUS_TOPOLOGY,
                               tree_parent(broadcast_candidate), broadcast_candidate);
              end else if (fault_armed_q &&
                           (tree_parent(broadcast_candidate) == fault_source_q) &&
                           (broadcast_candidate == fault_destination_q)) begin
                retry_or_fail(tree_parent(broadcast_candidate), broadcast_candidate);
              end else begin
                edge_retry_q <= '0;
                broadcast_q[broadcast_candidate] <= 1'b1;
                rsp_local_values_q[(broadcast_candidate*DATA_W) +: DATA_W] <=
                  tree_accum_q[root_q];
              end
            end
          end

          A2A_SELECT: begin
            if (pair_index_q == PAIR_W'(NUM_NODES*NUM_NODES)) begin
              complete_operation();
            end else begin
              logic [NODE_W-1:0] selected_source, selected_destination;
              selected_source = NODE_W'(pair_index_q / NUM_NODES);
              selected_destination = NODE_W'(pair_index_q % NUM_NODES);
              pair_source_q <= selected_source;
              pair_destination_q <= selected_destination;
              edge_retry_q <= '0;
              hop_count_q <= '0;
              if (!participants_q[selected_source] || !participants_q[selected_destination]) begin
                pair_index_q <= pair_index_q + 1'b1;
              end else if (selected_source == selected_destination) begin
                rsp_alltoall_values_q[((selected_destination*NUM_NODES+selected_source)*DATA_W) +: DATA_W] <=
                  alltoall_input_q[((selected_source*NUM_NODES+selected_destination)*DATA_W) +: DATA_W];
                pair_index_q <= pair_index_q + 1'b1;
              end else begin
                current_q <= selected_source;
                state_q <= A2A_ROUTE;
              end
            end
          end

          A2A_ROUTE: begin
            if (hop_count_q >= MAX_HOPS) begin
              fail_operation(RCIF_COLL_STATUS_HOP_LIMIT, current_q, pair_destination_q);
            end else if (!hop_partition_valid) begin
              fail_operation(RCIF_COLL_STATUS_PARTITION, current_q, hop_destination);
            end else if (!hop_link_enabled || (hop_destination == current_q)) begin
              fail_operation(RCIF_COLL_STATUS_TOPOLOGY, current_q, hop_destination);
            end else if (hop_faulted) begin
              retry_or_fail(current_q, hop_destination);
            end else begin
              edge_retry_q <= '0;
              hop_count_q <= hop_count_q + 1'b1;
              current_q <= hop_destination;
              if (hop_destination == pair_destination_q) begin
                rsp_alltoall_values_q[((pair_destination_q*NUM_NODES+pair_source_q)*DATA_W) +: DATA_W] <=
                  alltoall_input_q[((pair_source_q*NUM_NODES+pair_destination_q)*DATA_W) +: DATA_W];
                pair_index_q <= pair_index_q + 1'b1;
                state_q <= A2A_SELECT;
              end
            end
          end

          default: state_q <= state_q;
        endcase
      end
    end
  end

  // A response is a commit record: failures never expose partial reductions or
  // partially routed MoE payloads. The response remains stable under pressure.
  assert property (@(posedge clk_i) disable iff (!rst_ni)
                   rsp_valid_o && !rsp_ready_i |=>
                   $stable({rsp_collective_id_o, rsp_status_o, rsp_retry_count_o,
                            rsp_fault_source_o, rsp_fault_destination_o,
                            rsp_committed_o, rsp_local_values_o,
                            rsp_alltoall_values_o}));
  assert property (@(posedge clk_i) disable iff (!rst_ni)
                   rsp_valid_o && (rsp_status_o != RCIF_COLL_STATUS_OK) |->
                   !rsp_committed_o);
  assert property (@(posedge clk_i) disable iff (!rst_ni)
                   rsp_valid_o && !rsp_committed_o |->
                   (rsp_local_values_o == '0) && (rsp_alltoall_values_o == '0));
endmodule
