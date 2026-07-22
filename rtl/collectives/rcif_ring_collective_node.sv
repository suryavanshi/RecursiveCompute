/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off SYNCASYNCNET */
module rcif_ring_collective_node #(
  parameter int NODE_ID = 0,
  parameter int NUM_NODES = 4,
  parameter int DATA_W = 32,
  parameter int FLIT_W = 128,
  parameter int PARTITION_ID = 1
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    init_i,
  input  logic                    start_i,
  input  logic [7:0]              collective_id_i,
  input  logic [DATA_W-1:0]       local_value_i,
  output logic                    tx_valid_o,
  input  logic                    tx_ready_i,
  output logic [FLIT_W-1:0]       tx_flit_o,
  input  logic                    rx_valid_i,
  output logic                    rx_ready_o,
  input  logic [FLIT_W-1:0]       rx_flit_i,
  output logic                    idle_o,
  output logic                    result_valid_o,
  output logic [DATA_W-1:0]       result_o,
  output logic                    protocol_error_o
);
  import rcif_collective_protocol_pkg::*;

  localparam int NEXT_NODE = (NODE_ID + 1) % NUM_NODES;
  localparam int HEADER_W = $bits(rcif_collective_header_t);
  localparam int VISITED_LSB = DATA_W;

  logic busy_q, finishing_q;
  logic [7:0] collective_id_q;
  logic [DATA_W-1:0] local_value_q;
  logic tx_valid_q;
  logic [FLIT_W-1:0] tx_flit_q;
  logic result_valid_q;
  logic [DATA_W-1:0] result_q;
  logic protocol_error_q;
  rcif_collective_header_t rx_header;
  logic [DATA_W-1:0] rx_data;
  logic [NUM_NODES-1:0] rx_visited;
  logic rx_header_valid;

  initial begin
    if (FLIT_W < HEADER_W + DATA_W + NUM_NODES)
      $error("collective flit is too narrow");
    if (NUM_NODES > 8) $error("distributed reference supports at most eight nodes");
  end

  assign rx_header = rcif_collective_header_t'(rx_flit_i[FLIT_W-1 -: HEADER_W]);
  assign rx_data = rx_flit_i[DATA_W-1:0];
  assign rx_visited = rx_flit_i[VISITED_LSB +: NUM_NODES];
  assign rx_header_valid =
    (rx_header.version == RCIF_COLLECTIVE_PROTOCOL_VERSION) &&
    (rx_header.opcode == RCIF_COLL_OP_RING_ALLREDUCE) &&
    (rx_header.partition_id == 8'(PARTITION_ID)) &&
    (rx_header.collective_id == collective_id_q) &&
    (rx_header.destination == 4'(NODE_ID)) &&
    (rx_header.header_crc == rcif_collective_header_crc(rx_header));

  assign tx_valid_o = tx_valid_q;
  assign tx_flit_o = tx_flit_q;
  assign rx_ready_o = busy_q && !tx_valid_q;
  assign idle_o = !busy_q && !tx_valid_q;
  assign result_valid_o = result_valid_q;
  assign result_o = result_q;
  assign protocol_error_o = protocol_error_q;

  function automatic logic [FLIT_W-1:0] make_flit(
    input logic [DATA_W-1:0] data,
    input logic [NUM_NODES-1:0] visited,
    input logic [2:0] phase,
    input logic [6:0] hop_limit,
    input logic [7:0] collective_id
  );
    rcif_collective_header_t header;
    logic [FLIT_W-1:0] flit;
    begin
      header = '0;
      header.version = RCIF_COLLECTIVE_PROTOCOL_VERSION;
      header.opcode = RCIF_COLL_OP_RING_ALLREDUCE;
      header.phase = phase;
      header.partition_id = 8'(PARTITION_ID);
      header.collective_id = collective_id;
      header.source = 4'(NODE_ID);
      header.destination = 4'(NEXT_NODE);
      header.hop_limit = hop_limit;
      header.header_crc = rcif_collective_header_crc(header);
      flit = '0;
      flit[DATA_W-1:0] = data;
      flit[VISITED_LSB +: NUM_NODES] = visited;
      flit[FLIT_W-1 -: HEADER_W] = header;
      return flit;
    end
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      busy_q <= 1'b0;
      finishing_q <= 1'b0;
      collective_id_q <= '0;
      local_value_q <= '0;
      tx_valid_q <= 1'b0;
      tx_flit_q <= '0;
      result_valid_q <= 1'b0;
      result_q <= '0;
      protocol_error_q <= 1'b0;
    end else begin
      if (init_i) begin
        busy_q <= 1'b1;
        finishing_q <= 1'b0;
        collective_id_q <= collective_id_i;
        local_value_q <= local_value_i;
        tx_valid_q <= 1'b0;
        result_valid_q <= 1'b0;
        result_q <= '0;
        protocol_error_q <= 1'b0;
      end

      if (start_i) begin
        tx_valid_q <= 1'b1;
        tx_flit_q <= make_flit(local_value_i, NUM_NODES'(1) << NODE_ID,
                               RCIF_COLL_PHASE_REDUCE, 7'(NUM_NODES+1),
                               collective_id_i);
      end

      if (tx_valid_q && tx_ready_i) begin
        tx_valid_q <= 1'b0;
        if (finishing_q) begin
          finishing_q <= 1'b0;
          busy_q <= 1'b0;
        end
      end

      if (rx_valid_i && rx_ready_o) begin
        if (!rx_header_valid || (rx_header.hop_limit == '0)) begin
          protocol_error_q <= 1'b1;
          busy_q <= 1'b0;
        end else if (rx_header.phase == RCIF_COLL_PHASE_REDUCE) begin
          if (NODE_ID == 0) begin
            if (rx_visited != {NUM_NODES{1'b1}}) begin
              protocol_error_q <= 1'b1;
              busy_q <= 1'b0;
            end else begin
              result_q <= rx_data;
              result_valid_q <= 1'b1;
              tx_valid_q <= 1'b1;
              tx_flit_q <= make_flit(rx_data, NUM_NODES'(1),
                                     RCIF_COLL_PHASE_BROADCAST,
                                     7'(NUM_NODES+1), collective_id_q);
            end
          end else if (rx_visited[NODE_ID]) begin
            protocol_error_q <= 1'b1;
            busy_q <= 1'b0;
          end else begin
            tx_valid_q <= 1'b1;
            tx_flit_q <= make_flit(rx_data + local_value_q,
                                   rx_visited | (NUM_NODES'(1) << NODE_ID),
                                   RCIF_COLL_PHASE_REDUCE,
                                   rx_header.hop_limit - 1'b1, collective_id_q);
          end
        end else if (rx_header.phase == RCIF_COLL_PHASE_BROADCAST) begin
          result_q <= rx_data;
          result_valid_q <= 1'b1;
          if (NODE_ID == 0) begin
            if (rx_visited != {NUM_NODES{1'b1}}) protocol_error_q <= 1'b1;
            busy_q <= 1'b0;
          end else if (rx_visited[NODE_ID]) begin
            protocol_error_q <= 1'b1;
            busy_q <= 1'b0;
          end else begin
            tx_valid_q <= 1'b1;
            finishing_q <= 1'b1;
            tx_flit_q <= make_flit(rx_data,
                                   rx_visited | (NUM_NODES'(1) << NODE_ID),
                                   RCIF_COLL_PHASE_BROADCAST,
                                   rx_header.hop_limit - 1'b1, collective_id_q);
          end
        end else begin
          protocol_error_q <= 1'b1;
          busy_q <= 1'b0;
        end
      end
    end
  end

  assert property (@(posedge clk_i) disable iff (!rst_ni)
                   tx_valid_o && !tx_ready_i |=> $stable(tx_flit_o));
  assert property (@(posedge clk_i) disable iff (!rst_ni)
                   result_valid_o |-> !protocol_error_o);
endmodule
