package rcif_types_pkg;
  import rcif_params_pkg::*;

  typedef struct packed {
    logic [RCIF_REQ_ID_W-1:0] request_id;
    logic [15:0] opcode;
    logic [15:0] flags;
    logic [RCIF_DATA_W-1:0] payload;
  } rcif_cmd_t;

  typedef struct packed {
    logic [RCIF_REQ_ID_W-1:0] request_id;
    logic [RCIF_STATUS_W-1:0] status;
    logic [RCIF_DATA_W-1:0] result;
  } rcif_cpl_t;
endpackage

