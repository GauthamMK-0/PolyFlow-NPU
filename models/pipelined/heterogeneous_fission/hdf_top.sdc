# ==============================================================================
# SDC Timing Constraints: hdf_top (Model 3: Heterogeneous Fission / PolyFlow-NPU)
# Target Operating Frequency: 300 MHz (Clock Period = 3.333 ns)
# ==============================================================================

# Clock definition (3.333 ns = 300 MHz target frequency)
create_clock -name clk -period 3.333 [get_ports clk]

# Clock uncertainty & transition
set_clock_uncertainty 0.050 [get_clocks clk]
set_clock_transition  0.050 [get_clocks clk]

# Input / Output Delays (15% clock period budget)
set_input_delay  0.500 -clock clk [all_inputs -no_clocks]
set_output_delay 0.500 -clock clk [all_outputs]

# Driving cell & load
set_driving_cell -lib_cell INVX1 [all_inputs -no_clocks]
set_load 0.010 [all_outputs]

# --- False Path Optimizations ---
# 1. Asynchronous active-low reset
set_false_path -from [get_ports rst_n]

# 2. Quasi-static configuration and partition boundary registers
set_false_path -from [get_ports cfg_split_col*]
set_false_path -from [get_ports cfg_update_strobe]
set_false_path -from [get_ports dataflow_mode*]
set_false_path -from [get_ports phase_tag*]
set_false_path -from [get_ports role_reassign*]
set_false_path -from [get_ports new_region_id_per_bank*]
set_false_path -from [get_ports new_role_per_bank*]
set_false_path -from [get_ports lifetime_init*]
