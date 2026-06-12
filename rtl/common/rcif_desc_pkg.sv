package rcif_desc_pkg;
  parameter logic [15:0] RCIF_OPCODE_NOP = 16'h0000;
  parameter logic [15:0] RCIF_OPCODE_ECHO = 16'h0001;
  parameter logic [15:0] RCIF_OPCODE_GET_COUNTER = 16'h0010;
  parameter logic [15:0] RCIF_OPCODE_KV_MAP = 16'h0020;
  parameter logic [15:0] RCIF_OPCODE_KV_TRANSLATE = 16'h0021;
  parameter logic [15:0] RCIF_OPCODE_DMA_COPY = 16'h0030;

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

  parameter logic [7:0] RCIF_COUNTER_ACCEPTED = 8'h00;
  parameter logic [7:0] RCIF_COUNTER_COMPLETED = 8'h01;
  parameter logic [7:0] RCIF_COUNTER_ERRORS = 8'h02;

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
endpackage
