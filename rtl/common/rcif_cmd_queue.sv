module rcif_cmd_queue #(
  parameter int DATA_W = 64,
  parameter int REQ_ID_W = 32,
  parameter int DEPTH = 4
) (
  input  logic                clk_i,
  input  logic                rst_ni,

  input  logic                enq_valid_i,
  output logic                enq_ready_o,
  input  logic [REQ_ID_W-1:0] enq_request_id_i,
  input  logic [15:0]         enq_opcode_i,
  input  logic [15:0]         enq_flags_i,
  input  logic [DATA_W-1:0]   enq_payload_i,

  output logic                deq_valid_o,
  input  logic                deq_ready_i,
  output logic [REQ_ID_W-1:0] deq_request_id_o,
  output logic [15:0]         deq_opcode_o,
  output logic [15:0]         deq_flags_o,
  output logic [DATA_W-1:0]   deq_payload_o
);
  localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
  localparam int COUNT_W = $clog2(DEPTH + 1);
  localparam logic [COUNT_W-1:0] DEPTH_COUNT = COUNT_W'(DEPTH);
  localparam logic [PTR_W-1:0] LAST_PTR = PTR_W'(DEPTH - 1);

  logic [REQ_ID_W-1:0] request_id_mem [DEPTH];
  logic [15:0] opcode_mem [DEPTH];
  logic [15:0] flags_mem [DEPTH];
  logic [DATA_W-1:0] payload_mem [DEPTH];

  logic [PTR_W-1:0] rd_ptr_q;
  logic [PTR_W-1:0] wr_ptr_q;
  logic [COUNT_W-1:0] count_q;

  wire pop = deq_valid_o && deq_ready_i;
  wire push = enq_valid_i && enq_ready_o;

  assign enq_ready_o = (count_q < DEPTH_COUNT) || pop;
  assign deq_valid_o = (count_q != '0);
  assign deq_request_id_o = request_id_mem[rd_ptr_q];
  assign deq_opcode_o = opcode_mem[rd_ptr_q];
  assign deq_flags_o = flags_mem[rd_ptr_q];
  assign deq_payload_o = payload_mem[rd_ptr_q];

  function automatic logic [PTR_W-1:0] ptr_inc(input logic [PTR_W-1:0] ptr);
    if (ptr == LAST_PTR) begin
      ptr_inc = '0;
    end else begin
      ptr_inc = ptr + 1'b1;
    end
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_ptr_q <= '0;
      wr_ptr_q <= '0;
      count_q <= '0;
    end else begin
      if (push) begin
        request_id_mem[wr_ptr_q] <= enq_request_id_i;
        opcode_mem[wr_ptr_q] <= enq_opcode_i;
        flags_mem[wr_ptr_q] <= enq_flags_i;
        payload_mem[wr_ptr_q] <= enq_payload_i;
        wr_ptr_q <= ptr_inc(wr_ptr_q);
      end
      if (pop) begin
        rd_ptr_q <= ptr_inc(rd_ptr_q);
      end

      unique case ({push, pop})
        2'b10: count_q <= count_q + 1'b1;
        2'b01: count_q <= count_q - 1'b1;
        default: count_q <= count_q;
      endcase
    end
  end

`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert(count_q <= DEPTH_COUNT);
    end
  end
`endif
endmodule
