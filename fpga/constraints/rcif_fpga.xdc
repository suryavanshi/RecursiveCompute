# Board-neutral 100 MHz prototype clock. Board ports/pin locations belong in a
# vendor board overlay; this file intentionally contains no unsafe pin guesses.
create_clock -name rcif_clk -period 10.000 [get_ports clk_i]
set_false_path -from [get_ports rst_ni]
