module rcif_attention_mask_unit #(
  parameter int TOKEN_W = 16
) (
  input  logic [TOKEN_W-1:0] token_index_i,
  input  logic [TOKEN_W-1:0] context_tokens_i,
  input  logic [TOKEN_W-1:0] window_start_i,
  input  logic [TOKEN_W-1:0] sink_tokens_i,
  input  logic               explicit_enable_i,
  input  logic               explicit_keep_i,
  output logic               keep_o
);
  always_comb begin
    keep_o = (token_index_i < context_tokens_i) &&
             ((token_index_i < sink_tokens_i) ||
              (token_index_i >= window_start_i)) &&
             (!explicit_enable_i || explicit_keep_i);
  end
endmodule
