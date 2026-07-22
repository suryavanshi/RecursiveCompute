package rcif_desc_pkg;
  parameter logic [15:0] RCIF_OPCODE_NOP = 16'h0000;
  parameter logic [15:0] RCIF_OPCODE_ECHO = 16'h0001;
  parameter logic [15:0] RCIF_OPCODE_GET_COUNTER = 16'h0010;
  parameter logic [15:0] RCIF_OPCODE_KV_MAP = 16'h0020;
  parameter logic [15:0] RCIF_OPCODE_KV_TRANSLATE = 16'h0021;
  parameter logic [15:0] RCIF_OPCODE_KV_GET_FAULT = 16'h0022;
  parameter logic [15:0] RCIF_OPCODE_DMA_COPY = 16'h0030;
  parameter logic [15:0] RCIF_OPCODE_DMA_INDEX_WRITE = 16'h0031;
  parameter logic [15:0] RCIF_OPCODE_DMA_GATHER = 16'h0032;
  parameter logic [15:0] RCIF_OPCODE_DMA_ECC_INJECT = 16'h0033;
  parameter logic [15:0] RCIF_OPCODE_ATTN_QK_DOT = 16'h0040;

  parameter logic [31:0] RCIF_STATUS_OK = 32'h0000_0000;
  parameter logic [31:0] RCIF_STATUS_UNSUPPORTED_OPCODE = 32'h0000_0001;
  parameter logic [31:0] RCIF_STATUS_UNSUPPORTED_FLAGS = 32'h0000_0002;
  parameter logic [31:0] RCIF_STATUS_UNSUPPORTED_COUNTER = 32'h0000_0003;
  parameter logic [31:0] RCIF_STATUS_KV_MISS = 32'h0000_0004;
  parameter logic [31:0] RCIF_STATUS_KV_FULL = 32'h0000_0005;
  parameter logic [31:0] RCIF_STATUS_KV_RESERVED_BITS = 32'h0000_0006;
  parameter logic [31:0] RCIF_STATUS_DMA_ZERO_LENGTH = 32'h0000_0007;
  parameter logic [31:0] RCIF_STATUS_DMA_RESERVED_BITS = 32'h0000_0008;
  parameter logic [31:0] RCIF_STATUS_DMA_RANGE = 32'h0000_0009;
  parameter logic [31:0] RCIF_STATUS_FAULT_QUEUE_EMPTY = 32'h0000_000a;
  parameter logic [31:0] RCIF_STATUS_DMA_INDEX_MISS = 32'h0000_000b;
  parameter logic [31:0] RCIF_STATUS_DMA_ECC = 32'h0000_000c;
  parameter logic [31:0] RCIF_STATUS_GRAPH_INVALID = 32'h0000_000d;
  parameter logic [31:0] RCIF_STATUS_GRAPH_DEADLOCK = 32'h0000_000e;
  parameter logic [31:0] RCIF_STATUS_TENSOR_CONFIG = 32'h0000_000f;

  parameter logic [3:0] RCIF_GRAPH_OP_NOP = 4'h0;
  parameter logic [3:0] RCIF_GRAPH_OP_DMA = 4'h1;
  parameter logic [3:0] RCIF_GRAPH_OP_ATTN = 4'h2;
  parameter logic [3:0] RCIF_GRAPH_OP_TENSOR = 4'h3;
  parameter logic [3:0] RCIF_GRAPH_OP_COMPLETE = 4'hf;

  parameter logic [3:0] RCIF_GRAPH_DMA_COPY = 4'h0;
  parameter logic [3:0] RCIF_GRAPH_DMA_GATHER = 4'h1;
  parameter logic [3:0] RCIF_GRAPH_TENSOR_USE_PREV = 4'h8;

  parameter logic [7:0] RCIF_COUNTER_ACCEPTED = 8'h00;
  parameter logic [7:0] RCIF_COUNTER_COMPLETED = 8'h01;
  parameter logic [7:0] RCIF_COUNTER_ERRORS = 8'h02;
  parameter logic [7:0] RCIF_COUNTER_FAULT_OVERFLOWS = 8'h03;

  parameter int RCIF_KV_VIRT_PAGE_LSB = 0;
  parameter int RCIF_KV_VIRT_PAGE_W = 16;
  parameter int RCIF_KV_PHYS_PAGE_LSB = 16;
  parameter int RCIF_KV_PHYS_PAGE_W = 16;
  parameter int RCIF_KV_TIER_LSB = 32;
  parameter int RCIF_KV_TIER_W = 4;
  parameter int RCIF_KV_FORMAT_LSB = 36;
  parameter int RCIF_KV_FORMAT_W = 4;

  parameter int RCIF_DMA_SRC_PAGE_LSB = 0;
  parameter int RCIF_DMA_SRC_PAGE_W = 16;
  parameter int RCIF_DMA_DST_PAGE_LSB = 16;
  parameter int RCIF_DMA_DST_PAGE_W = 16;
  parameter int RCIF_DMA_LENGTH_LSB = 32;
  parameter int RCIF_DMA_LENGTH_W = 16;

  parameter int RCIF_DMA_INDEX_SLOT_LSB = 0;
  parameter int RCIF_DMA_INDEX_SLOT_W = 8;
  parameter int RCIF_DMA_INDEX_PAGE_LSB = 8;
  parameter int RCIF_DMA_INDEX_PAGE_W = 16;
endpackage
