module rcif_attn_engine #(
  parameter int ELEM_W = 8,
  parameter int OUT_W = 16,
  parameter int VEC_LEN = 4,
  parameter int SCORE_W = 32,
  parameter int MAX_PAGES = 8,
  parameter int PAGE_TOKENS = 4,
  parameter int MAX_Q_HEADS = 8,
  parameter int MAX_KV_HEADS = 4
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,

  input  logic                         query_write_valid_i,
  input  logic [$clog2(MAX_Q_HEADS)-1:0] query_write_head_i,
  input  logic [(ELEM_W*VEC_LEN)-1:0]  query_write_data_i,
  input  logic                         page_write_valid_i,
  input  logic [$clog2(MAX_PAGES)-1:0] page_write_slot_i,
  input  logic [$clog2(MAX_PAGES)-1:0] page_write_phys_i,
  input  logic                         kv_write_valid_i,
  input  logic [$clog2(MAX_PAGES)-1:0] kv_write_phys_page_i,
  input  logic [$clog2(PAGE_TOKENS)-1:0] kv_write_offset_i,
  input  logic [$clog2(MAX_KV_HEADS)-1:0] kv_write_head_i,
  input  logic [(ELEM_W*VEC_LEN)-1:0]  kv_write_key_i,
  input  logic [(ELEM_W*VEC_LEN)-1:0]  kv_write_value_i,

  input  logic                         req_valid_i,
  output logic                         req_ready_o,
  input  logic [$clog2(MAX_Q_HEADS)-1:0] req_query_head_i,
  input  logic [$clog2(MAX_Q_HEADS+1)-1:0] req_num_query_heads_i,
  input  logic [$clog2(MAX_KV_HEADS+1)-1:0] req_num_kv_heads_i,
  input  logic [$clog2(MAX_PAGES*PAGE_TOKENS+1)-1:0] req_context_tokens_i,
  input  logic [$clog2(MAX_PAGES*PAGE_TOKENS+1)-1:0] req_window_start_i,
  input  logic [$clog2(MAX_PAGES*PAGE_TOKENS+1)-1:0] req_sink_tokens_i,
  input  logic                         req_explicit_mask_enable_i,
  input  logic [(MAX_PAGES*PAGE_TOKENS)-1:0] req_explicit_mask_i,

  output logic                         rsp_valid_o,
  input  logic                         rsp_ready_i,
  output logic                         rsp_all_masked_o,
  output logic [(OUT_W*VEC_LEN)-1:0]   rsp_context_o
);
  localparam int MAX_TOKENS = MAX_PAGES * PAGE_TOKENS;
  localparam int TOKEN_W = $clog2(MAX_TOKENS+1);
  localparam int VEC_W = ELEM_W * VEC_LEN;
  localparam int ACC_W = 48;

  typedef enum logic [2:0] {IDLE, START, RUN, DRAIN, FINISH, REDUCE, RESPOND} state_t;
  state_t state_q;

  logic [VEC_W-1:0] query_mem [0:MAX_Q_HEADS-1];
  logic [VEC_W-1:0] query_q;
  logic [$clog2(MAX_KV_HEADS)-1:0] kv_head_q;
  logic [TOKEN_W-1:0] context_tokens_q, window_start_q, sink_tokens_q;
  logic explicit_mask_enable_q;
  logic [MAX_TOKENS-1:0] explicit_mask_q;
  logic [TOKEN_W-1:0] issue_token_q;

  logic mask_keep;
  logic reader_req_valid, reader_req_ready;
  logic reader_rsp_valid, reader_rsp_ready;
  logic [VEC_W-1:0] reader_key, reader_value;
  logic dot_req_valid, dot_req_ready, dot_rsp_valid, dot_rsp_ready;
  logic signed [SCORE_W-1:0] dot_rsp;
  logic [VEC_W-1:0] value_pipe_q;
  logic softmax_start, softmax_step_valid, softmax_step_ready, softmax_finish;
  logic softmax_result_valid, softmax_result_ready, softmax_empty;
  logic [ACC_W-1:0] softmax_denominator;
  logic [(ACC_W*VEC_LEN)-1:0] softmax_accumulator;
  logic reduce_req_ready, reduce_rsp_valid;
  logic reduce_rsp_empty;
  logic [(OUT_W*VEC_LEN)-1:0] reduce_rsp_context;

  wire issue_in_range = issue_token_q < context_tokens_q;
  wire request_config_valid = (req_num_query_heads_i > 0) &&
                              (req_num_query_heads_i <= $clog2(MAX_Q_HEADS+1)'(MAX_Q_HEADS)) &&
                              (req_num_kv_heads_i > 0) &&
                              (req_num_kv_heads_i <= $clog2(MAX_KV_HEADS+1)'(MAX_KV_HEADS)) &&
                              ($clog2(MAX_Q_HEADS+1)'(req_num_kv_heads_i) <= req_num_query_heads_i) &&
                              ($clog2(MAX_Q_HEADS+1)'(req_query_head_i) < req_num_query_heads_i) &&
                              (req_context_tokens_i <= TOKEN_W'(MAX_TOKENS));
  wire issue_mask_bit = (issue_token_q < TOKEN_W'(MAX_TOKENS)) ?
                        explicit_mask_q[issue_token_q[$clog2(MAX_TOKENS)-1:0]] : 1'b0;
  wire reader_to_dot = reader_rsp_valid && dot_req_ready;
  wire pipeline_empty = !reader_rsp_valid && !dot_rsp_valid;

  assign req_ready_o = (state_q == IDLE);
  assign rsp_valid_o = (state_q == RESPOND) && reduce_rsp_valid;
  assign rsp_all_masked_o = reduce_rsp_empty;
  assign rsp_context_o = reduce_rsp_context;

  rcif_attention_mask_unit #(.TOKEN_W(TOKEN_W)) u_mask (
    .token_index_i(issue_token_q),
    .context_tokens_i(context_tokens_q),
    .window_start_i(window_start_q),
    .sink_tokens_i(sink_tokens_q),
    .explicit_enable_i(explicit_mask_enable_q),
    .explicit_keep_i(issue_mask_bit),
    .keep_o(mask_keep)
  );

  assign reader_req_valid = (state_q == RUN) && issue_in_range && mask_keep;
  assign reader_rsp_ready = dot_req_ready;

  rcif_kv_page_reader #(
    .ELEM_W(ELEM_W), .VEC_LEN(VEC_LEN), .MAX_PAGES(MAX_PAGES),
    .PAGE_TOKENS(PAGE_TOKENS), .MAX_KV_HEADS(MAX_KV_HEADS)
  ) u_page_reader (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .page_write_valid_i(page_write_valid_i),
    .page_write_slot_i(page_write_slot_i), .page_write_phys_i(page_write_phys_i),
    .kv_write_valid_i(kv_write_valid_i), .kv_write_phys_page_i(kv_write_phys_page_i),
    .kv_write_offset_i(kv_write_offset_i), .kv_write_head_i(kv_write_head_i),
    .kv_write_key_i(kv_write_key_i), .kv_write_value_i(kv_write_value_i),
    .req_valid_i(reader_req_valid), .req_ready_o(reader_req_ready),
    .req_token_i(issue_token_q[$clog2(MAX_TOKENS)-1:0]), .req_head_i(kv_head_q),
    .rsp_valid_o(reader_rsp_valid), .rsp_ready_i(reader_rsp_ready),
    .rsp_key_o(reader_key), .rsp_value_o(reader_value)
  );

  assign dot_req_valid = reader_rsp_valid;
  rcif_qk_dot_array #(.ELEM_W(ELEM_W), .VEC_LEN(VEC_LEN), .ACC_W(SCORE_W)) u_qk (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .req_valid_i(dot_req_valid), .req_ready_o(dot_req_ready),
    .req_query_i(query_q), .req_key_i(reader_key),
    .rsp_valid_o(dot_rsp_valid), .rsp_ready_i(dot_rsp_ready), .rsp_dot_o(dot_rsp)
  );

  assign softmax_step_valid = dot_rsp_valid;
  assign dot_rsp_ready = softmax_step_ready;
  rcif_online_softmax #(
    .SCORE_W(SCORE_W), .ELEM_W(ELEM_W), .VEC_LEN(VEC_LEN), .ACC_W(ACC_W)
  ) u_softmax (
    .clk_i(clk_i), .rst_ni(rst_ni), .start_i(softmax_start),
    .step_valid_i(softmax_step_valid), .step_ready_o(softmax_step_ready),
    .step_score_i(dot_rsp), .step_value_i(value_pipe_q), .finish_i(softmax_finish),
    .result_valid_o(softmax_result_valid), .result_ready_i(softmax_result_ready),
    .result_empty_o(softmax_empty), .result_denominator_o(softmax_denominator),
    .result_accumulator_o(softmax_accumulator)
  );

  assign softmax_result_ready = (state_q == REDUCE) && reduce_req_ready;
  rcif_v_reduce #(.OUT_W(OUT_W), .VEC_LEN(VEC_LEN), .ACC_W(ACC_W)) u_reduce (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .req_valid_i((state_q == REDUCE) && softmax_result_valid), .req_ready_o(reduce_req_ready),
    .req_empty_i(softmax_empty), .req_denominator_i(softmax_denominator),
    .req_accumulator_i(softmax_accumulator), .rsp_valid_o(reduce_rsp_valid),
    .rsp_ready_i((state_q == RESPOND) && rsp_ready_i),
    .rsp_empty_o(reduce_rsp_empty), .rsp_context_o(reduce_rsp_context)
  );

  assign softmax_start = (state_q == START);
  assign softmax_finish = (state_q == FINISH);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      query_q <= '0;
      kv_head_q <= '0;
      context_tokens_q <= '0;
      window_start_q <= '0;
      sink_tokens_q <= '0;
      explicit_mask_enable_q <= 1'b0;
      explicit_mask_q <= '0;
      issue_token_q <= '0;
      value_pipe_q <= '0;
      for (int head = 0; head < MAX_Q_HEADS; head++) begin
        query_mem[head] <= '0;
      end
    end else begin
      if (query_write_valid_i) begin
        query_mem[query_write_head_i] <= query_write_data_i;
      end
      if (reader_to_dot) begin
        value_pipe_q <= reader_value;
      end
      unique case (state_q)
        IDLE: if (req_valid_i) begin
          query_q <= query_mem[req_query_head_i];
          if (request_config_valid) begin
            kv_head_q <= $clog2(MAX_KV_HEADS)'((req_query_head_i * req_num_kv_heads_i) / req_num_query_heads_i);
            context_tokens_q <= req_context_tokens_i;
          end else begin
            kv_head_q <= '0;
            context_tokens_q <= '0;
          end
          window_start_q <= req_window_start_i;
          sink_tokens_q <= req_sink_tokens_i;
          explicit_mask_enable_q <= req_explicit_mask_enable_i;
          explicit_mask_q <= req_explicit_mask_i;
          issue_token_q <= '0;
          state_q <= START;
        end
        START: state_q <= (context_tokens_q == 0) ? FINISH : RUN;
        RUN: begin
          if (issue_in_range) begin
            if (!mask_keep || (reader_req_valid && reader_req_ready)) begin
              issue_token_q <= issue_token_q + 1'b1;
              if (issue_token_q + 1'b1 >= context_tokens_q) begin
                state_q <= DRAIN;
              end
            end
          end else begin
            state_q <= DRAIN;
          end
        end
        DRAIN: if (pipeline_empty) state_q <= FINISH;
        FINISH: state_q <= REDUCE;
        REDUCE: if (softmax_result_valid && reduce_req_ready) state_q <= RESPOND;
        RESPOND: if (reduce_rsp_valid && rsp_ready_i) state_q <= IDLE;
        default: state_q <= IDLE;
      endcase
    end
  end

`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_ni && req_valid_i && req_ready_o) begin
      assert(req_num_query_heads_i > 0);
      assert(req_num_kv_heads_i > 0);
      assert(req_num_kv_heads_i <= req_num_query_heads_i);
      assert(req_context_tokens_i <= MAX_TOKENS);
    end
  end
`endif
endmodule
