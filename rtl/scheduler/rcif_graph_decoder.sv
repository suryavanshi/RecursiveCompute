module rcif_graph_decoder #(
  parameter int DESC_W = 128,
  parameter int NODE_ID_W = 3,
  parameter int MAX_NODES = 8
) (
  input  logic [DESC_W-1:0]       descriptor_i,
  output logic [3:0]              opcode_o,
  output logic [3:0]              flags_o,
  output logic [NODE_ID_W-1:0]    node_id_o,
  output logic [MAX_NODES-1:0]    dependency_mask_o,
  output logic [63:0]             operand0_o,
  output logic [31:0]             operand1_o,
  output logic                    valid_o
);
  import rcif_desc_pkg::*;

  logic [3:0] encoded_node_id;
  logic opcode_valid;
  logic flags_valid;

  assign opcode_o = descriptor_i[3:0];
  assign flags_o = descriptor_i[7:4];
  assign encoded_node_id = descriptor_i[11:8];
  assign node_id_o = encoded_node_id[NODE_ID_W-1:0];
  assign dependency_mask_o = descriptor_i[19:12];
  assign operand0_o = descriptor_i[83:20];
  assign operand1_o = descriptor_i[115:84];

  always_comb begin
    flags_valid = 1'b0;
    unique case (opcode_o)
      RCIF_GRAPH_OP_NOP,
      RCIF_GRAPH_OP_ATTN,
      RCIF_GRAPH_OP_COMPLETE: begin
        opcode_valid = 1'b1;
        flags_valid = (flags_o == 0);
      end
      RCIF_GRAPH_OP_DMA: begin
        opcode_valid = 1'b1;
        flags_valid = (flags_o[3:1] == 0);
      end
      RCIF_GRAPH_OP_TENSOR: begin
        opcode_valid = 1'b1;
        flags_valid = (flags_o[2:0] == 0);
      end
      default: begin
        opcode_valid = 1'b0;
        flags_valid = 1'b0;
      end
    endcase
  end

  assign valid_o = opcode_valid && flags_valid &&
                   (encoded_node_id < 4'(MAX_NODES)) &&
                   (descriptor_i[127:116] == '0);
endmodule
