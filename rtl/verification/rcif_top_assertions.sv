module rcif_top_assertions #(
  parameter int REQ_ID_W = 32,
  parameter int STATUS_W = 32,
  parameter int DATA_W = 64,
  parameter int MAX_OUTSTANDING = 5
) (
  input logic                clk_i,
  input logic                rst_ni,
  input logic                cmd_valid_i,
  input logic                cmd_ready_i,
  input logic                cpl_valid_i,
  input logic                cpl_ready_i,
  input logic [REQ_ID_W-1:0] cpl_request_id_i,
  input logic [STATUS_W-1:0] cpl_status_i,
  input logic [DATA_W-1:0]   cpl_result_i
);
  localparam int OUTSTANDING_W = $clog2(MAX_OUTSTANDING + 1);

  logic [OUTSTANDING_W-1:0] outstanding_q;
  logic held_valid_q;
  logic [REQ_ID_W-1:0] held_request_id_q;
  logic [STATUS_W-1:0] held_status_q;
  logic [DATA_W-1:0] held_result_q;

  wire accept = cmd_valid_i && cmd_ready_i;
  wire retire = cpl_valid_i && cpl_ready_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      outstanding_q <= '0;
      held_valid_q <= 1'b0;
      held_request_id_q <= '0;
      held_status_q <= '0;
      held_result_q <= '0;
    end else begin
      assert (!(retire && (outstanding_q == '0) && !accept))
        else $error("completion retired without an accepted command");
      assert (outstanding_q <= OUTSTANDING_W'(MAX_OUTSTANDING))
        else $error("accepted-minus-completed count exceeded top-level capacity");

      if (held_valid_q) begin
        assert (cpl_valid_i)
          else $error("completion valid dropped under backpressure");
        assert (cpl_request_id_i == held_request_id_q &&
                cpl_status_i == held_status_q &&
                cpl_result_i == held_result_q)
          else $error("completion payload changed under backpressure");
      end

      unique case ({accept, retire})
        2'b10: outstanding_q <= outstanding_q + 1'b1;
        2'b01: outstanding_q <= outstanding_q - 1'b1;
        default: outstanding_q <= outstanding_q;
      endcase

      held_valid_q <= cpl_valid_i && !cpl_ready_i;
      if (cpl_valid_i && !cpl_ready_i) begin
        held_request_id_q <= cpl_request_id_i;
        held_status_q <= cpl_status_i;
        held_result_q <= cpl_result_i;
      end
    end
  end
endmodule
