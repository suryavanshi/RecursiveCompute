set root [file normalize [file join [file dirname [info script]] ../..]]
set part [expr {[info exists ::env(RCIF_FPGA_PART)] ? $::env(RCIF_FPGA_PART) : "xcvu9p-flga2104-2L-e"}]
file mkdir $root/build
read_verilog -sv [glob $root/rtl/common/*.sv]
read_verilog -sv [glob $root/rtl/dma/*.sv]
read_verilog -sv [glob $root/rtl/attention/*.sv]
read_verilog -sv [glob $root/rtl/tensor/*.sv]
read_verilog -sv [glob $root/rtl/scheduler/*.sv]
read_verilog -sv [glob $root/fpga/rtl/*.sv]
read_xdc $root/fpga/constraints/rcif_fpga.xdc
synth_design -top rcif_fpga_top -part $part -flatten_hierarchy rebuilt
report_utilization -file $root/build/fpga_utilization.rpt
report_timing_summary -file $root/build/fpga_timing.rpt
write_checkpoint -force $root/build/rcif_fpga_synth.dcp
