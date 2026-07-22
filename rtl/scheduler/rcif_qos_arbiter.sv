module rcif_qos_arbiter #(
  parameter int REQUESTS = 4,
  parameter int PRIORITY_W = 2,
  parameter int AGE_W = 16,
  parameter int INDEX_W = $clog2(REQUESTS)
) (
  input  logic [REQUESTS-1:0]                 valid_i,
  input  logic [(REQUESTS*PRIORITY_W)-1:0]    priority_i,
  input  logic [(REQUESTS*AGE_W)-1:0]         age_i,
  output logic                                grant_valid_o,
  output logic [INDEX_W-1:0]                  grant_index_o
);
  logic [PRIORITY_W-1:0] best_priority;
  logic [AGE_W-1:0] best_age;

  always_comb begin
    grant_valid_o = 1'b0;
    grant_index_o = '0;
    best_priority = '0;
    best_age = '1;
    for (int index = 0; index < REQUESTS; index++) begin
      if (valid_i[index] &&
          (!grant_valid_o ||
           priority_i[(index*PRIORITY_W) +: PRIORITY_W] > best_priority ||
           ((priority_i[(index*PRIORITY_W) +: PRIORITY_W] == best_priority) &&
            (age_i[(index*AGE_W) +: AGE_W] < best_age)))) begin
        grant_valid_o = 1'b1;
        grant_index_o = INDEX_W'(index);
        best_priority = priority_i[(index*PRIORITY_W) +: PRIORITY_W];
        best_age = age_i[(index*AGE_W) +: AGE_W];
      end
    end
  end
endmodule
