module rcif_token_scheduler #(
  parameter int DATA_W = 64,
  parameter int REQ_ID_W = 32,
  parameter int STATUS_W = 32,
  parameter int MAX_DESCRIPTORS = 32,
  parameter int MAX_NODES = 8,
  parameter int REQUEST_SLOTS = 4,
  parameter int TRACE_DEPTH = 64,
  parameter int MAX_GRAPH_CYCLES = 6400,
  parameter int QOS_MAX_LATENCY_CYCLES = (REQUEST_SLOTS+1)*MAX_GRAPH_CYCLES,
  parameter int ATTN_MAX_PAGES = 8,
  parameter int ATTN_PAGE_TOKENS = 4,
  parameter int ATTN_MAX_Q_HEADS = 8,
  parameter int ATTN_MAX_KV_HEADS = 4,
  parameter int LANES = 4
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,

  input  logic                         graph_write_valid_i,
  output logic                         graph_write_ready_o,
  input  logic [$clog2(MAX_DESCRIPTORS)-1:0] graph_write_index_i,
  input  logic [127:0]                 graph_write_descriptor_i,

  input  logic                         req_valid_i,
  output logic                         req_ready_o,
  input  logic [REQ_ID_W-1:0]          req_request_id_i,
  input  logic [$clog2(MAX_DESCRIPTORS)-1:0] req_graph_base_i,
  input  logic [$clog2(MAX_NODES+1)-1:0] req_graph_nodes_i,
  input  logic [1:0]                   req_priority_i,

  input  logic                         query_write_valid_i,
  input  logic [$clog2(ATTN_MAX_Q_HEADS)-1:0] query_write_head_i,
  input  logic [(8*LANES)-1:0]         query_write_data_i,
  input  logic                         page_write_valid_i,
  input  logic [$clog2(ATTN_MAX_PAGES)-1:0] page_write_slot_i,
  input  logic [$clog2(ATTN_MAX_PAGES)-1:0] page_write_phys_i,
  input  logic                         kv_write_valid_i,
  input  logic [$clog2(ATTN_MAX_PAGES)-1:0] kv_write_phys_page_i,
  input  logic [$clog2(ATTN_PAGE_TOKENS)-1:0] kv_write_offset_i,
  input  logic [$clog2(ATTN_MAX_KV_HEADS)-1:0] kv_write_head_i,
  input  logic [(8*LANES)-1:0]         kv_write_key_i,
  input  logic [(8*LANES)-1:0]         kv_write_value_i,

  input  logic                         weight_write_valid_i,
  output logic                         weight_write_ready_o,
  input  logic [$clog2(LANES)-1:0]     weight_write_row_i,
  input  logic [1:0]                   weight_write_format_i,
  input  logic [31:0]                  weight_write_data_i,
  input  logic signed [7:0]            weight_write_zero_point_i,
  input  logic signed [15:0]           weight_write_scale_q8_8_i,
  input  logic signed [31:0]           weight_write_bias_i,
  input  logic signed [15:0]           weight_write_norm_gain_q8_8_i,

  output logic                         cpl_valid_o,
  input  logic                         cpl_ready_i,
  output logic [REQ_ID_W-1:0]          cpl_request_id_o,
  output logic [STATUS_W-1:0]          cpl_status_o,
  output logic [DATA_W-1:0]            cpl_result_o,

  input  logic                         trace_clear_i,
  input  logic [$clog2(TRACE_DEPTH)-1:0] trace_read_index_i,
  output logic [127:0]                 trace_read_event_o,
  output logic [$clog2(TRACE_DEPTH):0] trace_event_count_o,
  output logic                         trace_overflow_o,

  output logic [15:0]                  qos_bound_cycles_o,
  output logic [15:0]                  qos_last_latency_o,
  output logic [REQ_ID_W-1:0]          qos_last_request_id_o,
  output logic                         qos_bound_violation_o
);
  import rcif_desc_pkg::*;

  localparam int DESC_INDEX_W = $clog2(MAX_DESCRIPTORS);
  localparam int NODE_ID_W = $clog2(MAX_NODES);
  localparam int NODE_COUNT_W = $clog2(MAX_NODES+1);
  localparam int SLOT_W = $clog2(REQUEST_SLOTS);

  typedef enum logic [3:0] {
    IDLE, LOAD, SCAN, EXEC_IMMEDIATE, WAIT_DMA, WAIT_ATTN,
    WAIT_TENSOR, FINISH
  } state_t;

  logic [127:0] descriptor_mem [0:MAX_DESCRIPTORS-1];
  logic [REQUEST_SLOTS-1:0] request_valid_q;
  logic [REQ_ID_W-1:0] request_id_mem [0:REQUEST_SLOTS-1];
  logic [DESC_INDEX_W-1:0] request_base_mem [0:REQUEST_SLOTS-1];
  logic [NODE_COUNT_W-1:0] request_nodes_mem [0:REQUEST_SLOTS-1];
  logic [1:0] request_priority_mem [0:REQUEST_SLOTS-1];
  logic [15:0] request_age_mem [0:REQUEST_SLOTS-1];
  logic [15:0] request_wait_mem [0:REQUEST_SLOTS-1];
  logic [15:0] age_counter_q;
  logic [REQUEST_SLOTS-1:0] free_mask;
  logic [SLOT_W-1:0] free_index;
  logic qos_grant_valid;
  logic [SLOT_W-1:0] qos_grant_index;
  logic [(REQUEST_SLOTS*2)-1:0] qos_priorities;
  logic [(REQUEST_SLOTS*16)-1:0] qos_ages;

  state_t state_q;
  logic [REQ_ID_W-1:0] active_request_id_q;
  logic [DESC_INDEX_W-1:0] active_base_q;
  logic [NODE_COUNT_W-1:0] active_nodes_q;
  logic [NODE_COUNT_W-1:0] scan_index_q;
  logic [DATA_W-1:0] accumulated_result_q;
  logic [31:0] last_result_q;
  logic [1:0] active_priority_q;
  logic [15:0] active_latency_q;
  logic [15:0] active_service_cycles_q;
  logic retire_recorded_q;
  logic [15:0] qos_last_latency_q;
  logic [REQ_ID_W-1:0] qos_last_request_id_q;
  logic qos_bound_violation_q;
  logic [NODE_ID_W-1:0] issued_node_id_q;
  logic [3:0] issued_opcode_q;
  logic [63:0] issued_operand0_q;
  logic [31:0] issued_operand1_q;

  logic [127:0] decoded_descriptor;
  logic [3:0] decoded_opcode, decoded_flags;
  logic [NODE_ID_W-1:0] decoded_node_id;
  logic [MAX_NODES-1:0] decoded_dependencies;
  logic [63:0] decoded_operand0;
  logic [31:0] decoded_operand1;
  logic decoded_valid;
  logic scoreboard_clear, scoreboard_complete;
  logic dependencies_ready;
  logic [MAX_NODES-1:0] completed_mask;

  logic dma_req_valid, dma_req_ready, dma_rsp_valid, dma_rsp_ready;
  logic [15:0] dma_req_opcode;
  logic [STATUS_W-1:0] dma_rsp_status;
  logic [DATA_W-1:0] dma_rsp_result;
  logic attn_req_valid, attn_req_ready, attn_rsp_valid, attn_rsp_ready;
  logic attn_rsp_all_masked;
  logic [(16*LANES)-1:0] attn_rsp_context;
  logic tensor_req_valid, tensor_req_ready, tensor_rsp_valid, tensor_rsp_ready;
  logic [(16*LANES)-1:0] tensor_rsp_result;
  logic [LANES-1:0] tensor_rsp_saturated;
  logic tensor_rsp_config_error;

  logic completion_push_valid, completion_push_ready;
  logic [STATUS_W-1:0] completion_status;
  logic [DATA_W-1:0] completion_result;
  logic trace_event_valid;
  logic [127:0] trace_event;

  wire request_config_valid = (req_graph_nodes_i > 0) &&
                              (req_graph_nodes_i <= NODE_COUNT_W'(MAX_NODES)) &&
                              ((32'(req_graph_base_i) + 32'(req_graph_nodes_i)) <= MAX_DESCRIPTORS);
  wire accept_request = req_valid_i && req_ready_o;
  wire current_already_complete = completed_mask[decoded_node_id];
  wire current_ready = decoded_valid && !current_already_complete && dependencies_ready;

  assign qos_bound_cycles_o = 16'(QOS_MAX_LATENCY_CYCLES);
  assign qos_last_latency_o = qos_last_latency_q;
  assign qos_last_request_id_o = qos_last_request_id_q;
  assign qos_bound_violation_o = qos_bound_violation_q;

  always_comb begin
    free_mask = ~request_valid_q;
    free_index = '0;
    req_ready_o = request_config_valid && (free_mask != '0);
    for (int slot = REQUEST_SLOTS-1; slot >= 0; slot--) begin
      if (free_mask[slot]) free_index = SLOT_W'(slot);
      qos_priorities[(slot*2) +: 2] = request_priority_mem[slot];
      qos_ages[(slot*16) +: 16] = request_age_mem[slot];
    end
  end

  assign graph_write_ready_o = 1'b1;
  assign decoded_descriptor = descriptor_mem[active_base_q + scan_index_q];
  assign dma_req_valid = (state_q == SCAN) && current_ready &&
                         (decoded_opcode == RCIF_GRAPH_OP_DMA);
  assign dma_req_opcode = (decoded_flags == RCIF_GRAPH_DMA_GATHER) ?
                          RCIF_OPCODE_DMA_GATHER : RCIF_OPCODE_DMA_COPY;
  assign dma_rsp_ready = (state_q == WAIT_DMA);
  assign attn_req_valid = (state_q == SCAN) && current_ready &&
                          (decoded_opcode == RCIF_GRAPH_OP_ATTN);
  assign attn_rsp_ready = (state_q == WAIT_ATTN);
  assign tensor_req_valid = (state_q == SCAN) && current_ready &&
                            (decoded_opcode == RCIF_GRAPH_OP_TENSOR);
  assign tensor_rsp_ready = (state_q == WAIT_TENSOR);
  assign scoreboard_clear = (state_q == LOAD);

  rcif_graph_decoder #(.NODE_ID_W(NODE_ID_W), .MAX_NODES(MAX_NODES)) u_graph_decoder (
    .descriptor_i(decoded_descriptor), .opcode_o(decoded_opcode),
    .flags_o(decoded_flags), .node_id_o(decoded_node_id),
    .dependency_mask_o(decoded_dependencies), .operand0_o(decoded_operand0),
    .operand1_o(decoded_operand1), .valid_o(decoded_valid)
  );

  rcif_dependency_scoreboard #(.MAX_NODES(MAX_NODES)) u_scoreboard (
    .clk_i(clk_i), .rst_ni(rst_ni), .clear_i(scoreboard_clear),
    .complete_valid_i(scoreboard_complete), .complete_node_id_i(issued_node_id_q),
    .dependency_mask_i(decoded_dependencies), .dependencies_ready_o(dependencies_ready),
    .completed_mask_o(completed_mask)
  );

  rcif_qos_arbiter #(.REQUESTS(REQUEST_SLOTS)) u_qos (
    .valid_i(request_valid_q), .priority_i(qos_priorities), .age_i(qos_ages),
    .grant_valid_o(qos_grant_valid), .grant_index_o(qos_grant_index)
  );

  rcif_dma #(.DATA_W(DATA_W), .STATUS_W(STATUS_W)) u_dma (
    .clk_i(clk_i), .rst_ni(rst_ni), .req_valid_i(dma_req_valid),
    .req_ready_o(dma_req_ready), .req_opcode_i(dma_req_opcode),
    .req_payload_i(decoded_operand0), .rsp_valid_o(dma_rsp_valid),
    .rsp_ready_i(dma_rsp_ready), .rsp_status_o(dma_rsp_status),
    .rsp_result_o(dma_rsp_result)
  );

  rcif_attn_engine #(
    .ELEM_W(8), .OUT_W(16), .VEC_LEN(LANES), .MAX_PAGES(ATTN_MAX_PAGES),
    .PAGE_TOKENS(ATTN_PAGE_TOKENS), .MAX_Q_HEADS(ATTN_MAX_Q_HEADS),
    .MAX_KV_HEADS(ATTN_MAX_KV_HEADS)
  ) u_attention (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .query_write_valid_i(query_write_valid_i), .query_write_head_i(query_write_head_i),
    .query_write_data_i(query_write_data_i), .page_write_valid_i(page_write_valid_i),
    .page_write_slot_i(page_write_slot_i), .page_write_phys_i(page_write_phys_i),
    .kv_write_valid_i(kv_write_valid_i), .kv_write_phys_page_i(kv_write_phys_page_i),
    .kv_write_offset_i(kv_write_offset_i), .kv_write_head_i(kv_write_head_i),
    .kv_write_key_i(kv_write_key_i), .kv_write_value_i(kv_write_value_i),
    .req_valid_i(attn_req_valid), .req_ready_o(attn_req_ready),
    .req_query_head_i(decoded_operand0[2:0]),
    .req_num_query_heads_i(decoded_operand0[6:3]),
    .req_num_kv_heads_i(decoded_operand0[9:7]),
    .req_context_tokens_i(decoded_operand0[15:10]),
    .req_window_start_i(decoded_operand0[21:16]),
    .req_sink_tokens_i(decoded_operand0[27:22]),
    .req_explicit_mask_enable_i(decoded_operand0[28]),
    .req_explicit_mask_i(decoded_operand1), .rsp_valid_o(attn_rsp_valid),
    .rsp_ready_i(attn_rsp_ready), .rsp_all_masked_o(attn_rsp_all_masked),
    .rsp_context_o(attn_rsp_context)
  );

  rcif_tensor_array #(.LANES(LANES), .ACC_W(32), .OUT_W(16)) u_tensor (
    .clk_i(clk_i), .rst_ni(rst_ni), .weight_write_valid_i(weight_write_valid_i),
    .weight_write_ready_o(weight_write_ready_o), .weight_write_row_i(weight_write_row_i),
    .weight_write_format_i(weight_write_format_i), .weight_write_data_i(weight_write_data_i),
    .weight_write_zero_point_i(weight_write_zero_point_i),
    .weight_write_scale_q8_8_i(weight_write_scale_q8_8_i),
    .weight_write_bias_i(weight_write_bias_i),
    .weight_write_norm_gain_q8_8_i(weight_write_norm_gain_q8_8_i),
    .req_valid_i(tensor_req_valid), .req_ready_o(tensor_req_ready),
    .req_activation_i((decoded_flags == RCIF_GRAPH_TENSOR_USE_PREV) ?
                      last_result_q : decoded_operand0[31:0]),
    .req_activation_mode_i(decoded_operand1[1:0]),
    .req_norm_enable_i(decoded_operand1[2]), .req_norm_epsilon_i(decoded_operand1[18:3]),
    .rsp_valid_o(tensor_rsp_valid), .rsp_ready_i(tensor_rsp_ready),
    .rsp_result_o(tensor_rsp_result), .rsp_saturated_o(tensor_rsp_saturated),
    .rsp_config_error_o(tensor_rsp_config_error)
  );

  rcif_completion_writer #(.DEPTH(4)) u_completion_writer (
    .clk_i(clk_i), .rst_ni(rst_ni), .push_valid_i(completion_push_valid),
    .push_ready_o(completion_push_ready), .push_request_id_i(active_request_id_q),
    .push_status_i(completion_status), .push_result_i(completion_result),
    .cpl_valid_o(cpl_valid_o), .cpl_ready_i(cpl_ready_i),
    .cpl_request_id_o(cpl_request_id_o), .cpl_status_o(cpl_status_o),
    .cpl_result_o(cpl_result_o)
  );

  rcif_replay_trace #(.DEPTH(TRACE_DEPTH)) u_replay_trace (
    .clk_i(clk_i), .rst_ni(rst_ni), .clear_i(trace_clear_i),
    .event_valid_i(trace_event_valid), .event_i(trace_event),
    .read_index_i(trace_read_index_i), .read_event_o(trace_read_event_o),
    .event_count_o(trace_event_count_o), .overflow_o(trace_overflow_o)
  );

  always_comb begin
    scoreboard_complete = 1'b0;
    completion_push_valid = 1'b0;
    completion_status = RCIF_STATUS_OK[STATUS_W-1:0];
    completion_result = accumulated_result_q;
    trace_event_valid = 1'b0;
    trace_event = '0;

    if ((state_q == SCAN) && current_ready) begin
      trace_event_valid = 1'b1;
      trace_event[31:0] = active_request_id_q;
      trace_event[35:32] = decoded_opcode;
      trace_event[38:36] = decoded_node_id;
    end else if (state_q == EXEC_IMMEDIATE) begin
      scoreboard_complete = (issued_opcode_q != RCIF_GRAPH_OP_COMPLETE);
      trace_event_valid = 1'b1;
      trace_event[31:0] = active_request_id_q;
      trace_event[35:32] = issued_opcode_q;
      trace_event[38:36] = issued_node_id_q;
      trace_event[39] = 1'b1;
      trace_event[127:72] = issued_operand0_q[55:0];
    end else if ((state_q == WAIT_DMA) && dma_rsp_valid) begin
      scoreboard_complete = (dma_rsp_status == RCIF_STATUS_OK[STATUS_W-1:0]);
      trace_event_valid = 1'b1;
      trace_event[31:0] = active_request_id_q;
      trace_event[35:32] = issued_opcode_q;
      trace_event[38:36] = issued_node_id_q;
      trace_event[39] = 1'b1;
      trace_event[71:40] = dma_rsp_status;
      trace_event[127:72] = dma_rsp_result[55:0];
    end else if ((state_q == WAIT_ATTN) && attn_rsp_valid) begin
      scoreboard_complete = 1'b1;
      trace_event_valid = 1'b1;
      trace_event[31:0] = active_request_id_q;
      trace_event[35:32] = issued_opcode_q;
      trace_event[38:36] = issued_node_id_q;
      trace_event[39] = 1'b1;
      trace_event[40] = attn_rsp_all_masked;
      trace_event[127:72] = attn_rsp_context[55:0];
    end else if ((state_q == WAIT_TENSOR) && tensor_rsp_valid) begin
      scoreboard_complete = !tensor_rsp_config_error;
      trace_event_valid = 1'b1;
      trace_event[31:0] = active_request_id_q;
      trace_event[35:32] = issued_opcode_q;
      trace_event[38:36] = issued_node_id_q;
      trace_event[39] = 1'b1;
      trace_event[71:40] = tensor_rsp_config_error ? RCIF_STATUS_TENSOR_CONFIG : RCIF_STATUS_OK;
      trace_event[123:72] = tensor_rsp_result[51:0];
      trace_event[127:124] = tensor_rsp_saturated;
    end else if (state_q == FINISH) begin
      completion_push_valid = 1'b1;
      completion_status = issued_operand1_q[STATUS_W-1:0];
      completion_result = issued_operand0_q;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      request_valid_q <= '0;
      age_counter_q <= '0;
      state_q <= IDLE;
      active_request_id_q <= '0;
      active_base_q <= '0;
      active_nodes_q <= '0;
      scan_index_q <= '0;
      accumulated_result_q <= '0;
      last_result_q <= '0;
      active_priority_q <= '0;
      active_latency_q <= '0;
      active_service_cycles_q <= '0;
      retire_recorded_q <= 1'b0;
      qos_last_latency_q <= '0;
      qos_last_request_id_q <= '0;
      qos_bound_violation_q <= 1'b0;
      issued_node_id_q <= '0;
      issued_opcode_q <= '0;
      issued_operand0_q <= '0;
      issued_operand1_q <= '0;
      for (int slot = 0; slot < REQUEST_SLOTS; slot++) begin
        request_id_mem[slot] <= '0;
        request_base_mem[slot] <= '0;
        request_nodes_mem[slot] <= '0;
        request_priority_mem[slot] <= '0;
        request_age_mem[slot] <= '0;
        request_wait_mem[slot] <= '0;
      end
    end else begin
      if (graph_write_valid_i && graph_write_ready_o) begin
        descriptor_mem[graph_write_index_i] <= graph_write_descriptor_i;
      end
      for (int slot = 0; slot < REQUEST_SLOTS; slot++) begin
        if (request_valid_q[slot] && request_wait_mem[slot] != 16'hffff) begin
          request_wait_mem[slot] <= request_wait_mem[slot] + 1'b1;
        end
      end
      if ((state_q != IDLE) && (state_q != FINISH) && active_latency_q != 16'hffff) begin
        active_latency_q <= active_latency_q + 1'b1;
        if (active_service_cycles_q != 16'hffff) begin
          active_service_cycles_q <= active_service_cycles_q + 1'b1;
        end
        if (active_service_cycles_q >= 16'(MAX_GRAPH_CYCLES)) begin
          qos_bound_violation_q <= 1'b1;
        end
      end
      if ((state_q == FINISH) && !retire_recorded_q) begin
        qos_last_latency_q <= active_latency_q;
        qos_last_request_id_q <= active_request_id_q;
        retire_recorded_q <= 1'b1;
        if ((active_priority_q == 2'b11) &&
            (active_latency_q > 16'(QOS_MAX_LATENCY_CYCLES))) begin
          qos_bound_violation_q <= 1'b1;
        end
      end
      if (accept_request) begin
        request_valid_q[free_index] <= 1'b1;
        request_id_mem[free_index] <= req_request_id_i;
        request_base_mem[free_index] <= req_graph_base_i;
        request_nodes_mem[free_index] <= req_graph_nodes_i;
        request_priority_mem[free_index] <= req_priority_i;
        request_age_mem[free_index] <= age_counter_q;
        request_wait_mem[free_index] <= '0;
        age_counter_q <= age_counter_q + 1'b1;
      end

      unique case (state_q)
        IDLE: if (qos_grant_valid) begin
          active_request_id_q <= request_id_mem[qos_grant_index];
          active_base_q <= request_base_mem[qos_grant_index];
          active_nodes_q <= request_nodes_mem[qos_grant_index];
          active_priority_q <= request_priority_mem[qos_grant_index];
          active_latency_q <= request_wait_mem[qos_grant_index] + 1'b1;
          active_service_cycles_q <= '0;
          retire_recorded_q <= 1'b0;
          request_valid_q[qos_grant_index] <= 1'b0;
          accumulated_result_q <= '0;
          last_result_q <= '0;
          scan_index_q <= '0;
          state_q <= LOAD;
        end
        LOAD: state_q <= SCAN;
        SCAN: begin
          if (!decoded_valid) begin
            issued_operand0_q <= {{(DATA_W-NODE_COUNT_W){1'b0}}, scan_index_q};
            issued_operand1_q <= RCIF_STATUS_GRAPH_INVALID;
            state_q <= FINISH;
          end else if (current_already_complete || !dependencies_ready) begin
            if (scan_index_q + 1'b1 >= active_nodes_q) begin
              issued_operand0_q <= {{(64-MAX_NODES){1'b0}}, completed_mask};
              issued_operand1_q <= RCIF_STATUS_GRAPH_DEADLOCK;
              state_q <= FINISH;
            end else begin
              scan_index_q <= scan_index_q + 1'b1;
            end
          end else begin
            issued_node_id_q <= decoded_node_id;
            issued_opcode_q <= decoded_opcode;
            issued_operand0_q <= decoded_operand0;
            issued_operand1_q <= decoded_operand1;
            unique case (decoded_opcode)
              RCIF_GRAPH_OP_NOP: state_q <= EXEC_IMMEDIATE;
              RCIF_GRAPH_OP_COMPLETE: state_q <= EXEC_IMMEDIATE;
              RCIF_GRAPH_OP_DMA: if (dma_req_ready) state_q <= WAIT_DMA;
              RCIF_GRAPH_OP_ATTN: if (attn_req_ready) state_q <= WAIT_ATTN;
              RCIF_GRAPH_OP_TENSOR: if (tensor_req_ready) state_q <= WAIT_TENSOR;
              default: begin
                issued_operand0_q <= {{60{1'b0}}, decoded_opcode};
                issued_operand1_q <= RCIF_STATUS_GRAPH_INVALID;
                state_q <= FINISH;
              end
            endcase
          end
        end
        EXEC_IMMEDIATE: begin
          if (issued_opcode_q == RCIF_GRAPH_OP_COMPLETE) begin
            issued_operand0_q <= accumulated_result_q ^ issued_operand0_q;
            issued_operand1_q <= RCIF_STATUS_OK;
            state_q <= FINISH;
          end else begin
            accumulated_result_q <= accumulated_result_q ^ issued_operand0_q;
            last_result_q <= issued_operand0_q[31:0];
            scan_index_q <= '0;
            state_q <= SCAN;
          end
        end
        WAIT_DMA: if (dma_rsp_valid) begin
          if (dma_rsp_status != RCIF_STATUS_OK[STATUS_W-1:0]) begin
            issued_operand0_q <= dma_rsp_result;
            issued_operand1_q <= dma_rsp_status;
            state_q <= FINISH;
          end else begin
            accumulated_result_q <= accumulated_result_q ^ dma_rsp_result;
            last_result_q <= dma_rsp_result[31:0];
            scan_index_q <= '0;
            state_q <= SCAN;
          end
        end
        WAIT_ATTN: if (attn_rsp_valid) begin
          accumulated_result_q <= accumulated_result_q ^ attn_rsp_context;
          last_result_q <= attn_rsp_context[31:0];
          scan_index_q <= '0;
          state_q <= SCAN;
        end
        WAIT_TENSOR: if (tensor_rsp_valid) begin
          if (tensor_rsp_config_error) begin
            issued_operand0_q <= tensor_rsp_result;
            issued_operand1_q <= RCIF_STATUS_TENSOR_CONFIG;
            state_q <= FINISH;
          end else begin
            accumulated_result_q <= accumulated_result_q ^ tensor_rsp_result;
            last_result_q <= tensor_rsp_result[31:0];
            scan_index_q <= '0;
            state_q <= SCAN;
          end
        end
        FINISH: if (completion_push_ready) state_q <= IDLE;
        default: state_q <= IDLE;
      endcase
    end
  end
endmodule
