package rcif_collective_protocol_pkg;
  parameter logic [3:0] RCIF_COLLECTIVE_PROTOCOL_VERSION = 4'h1;

  parameter logic [2:0] RCIF_COLL_OP_RING_ALLREDUCE = 3'h0;
  parameter logic [2:0] RCIF_COLL_OP_TREE_ALLREDUCE = 3'h1;
  parameter logic [2:0] RCIF_COLL_OP_ALLTOALL = 3'h2;

  parameter logic [2:0] RCIF_COLL_PHASE_DATA = 3'h0;
  parameter logic [2:0] RCIF_COLL_PHASE_REDUCE = 3'h1;
  parameter logic [2:0] RCIF_COLL_PHASE_BROADCAST = 3'h2;
  parameter logic [2:0] RCIF_COLL_PHASE_ACK = 3'h3;
  parameter logic [2:0] RCIF_COLL_PHASE_RETRY = 3'h4;

  parameter logic [7:0] RCIF_COLL_STATUS_OK = 8'h00;
  parameter logic [7:0] RCIF_COLL_STATUS_BAD_COMMAND = 8'h01;
  parameter logic [7:0] RCIF_COLL_STATUS_TOPOLOGY = 8'h02;
  parameter logic [7:0] RCIF_COLL_STATUS_PARTITION = 8'h03;
  parameter logic [7:0] RCIF_COLL_STATUS_RETRY_EXHAUSTED = 8'h04;
  parameter logic [7:0] RCIF_COLL_STATUS_HOP_LIMIT = 8'h05;

  // Fixed header carried ahead of the parameterized payload. The header is
  // deliberately scalar so link adapters can parse and reject a packet before
  // admitting payload data to another tenant partition.
  typedef struct packed {
    logic [3:0] version;
    logic [2:0] opcode;
    logic [2:0] phase;
    logic [7:0] partition_id;
    logic [7:0] collective_id;
    logic [3:0] source;
    logic [3:0] destination;
    logic [3:0] chunk;
    logic [3:0] sequence_id;
    logic [6:0] hop_limit;
    logic [6:0] retry;
    logic [7:0] header_crc;
  } rcif_collective_header_t;

  function automatic logic [7:0] rcif_collective_header_crc(
    input rcif_collective_header_t header
  );
    logic [7:0] crc;
    logic [$bits(rcif_collective_header_t)-1:0] protected_bits;
    begin
      protected_bits = header;
      protected_bits[7:0] = '0;
      crc = 8'h5a;
      for (int bit_index = 0; bit_index < $bits(protected_bits); bit_index++) begin
        crc = {crc[6:0], crc[7] ^ protected_bits[bit_index]};
        if (crc[0]) crc ^= 8'h1d;
      end
      return crc;
    end
  endfunction
endpackage
