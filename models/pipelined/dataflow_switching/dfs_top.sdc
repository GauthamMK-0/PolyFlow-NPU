# ==============================================================================
# SDC Timing Constraints: dfs_top (Model 1: Dataflow Switching)
# Target Operating Frequency: 300 MHz (Clock Period = 3.333 ns)
# ==============================================================================

# Clock definition (3.333 ns = 300 MHz target frequency)
create_clock -name clk -period 3.333 [get_ports clk]

# Clock uncertainty & transition
set_clock_uncertainty 0.050 [get_clocks clk]
set_clock_transition  0.050 [get_clocks clk]

# Input / Output Delays (10% clock period budget)
set_input_delay  0.350 -clock clk [all_inputs -no_clocks]
set_output_delay 0.350 -clock clk [all_outputs]

# Driving cell & load
set_driving_cell -lib_cell INVX1 [all_inputs -no_clocks]
set_load 0.010 [all_outputs]

# --- False Path Optimizations ---
# 1. Asynchronous active-low reset
set_false_path -from [get_ports rst_n]

# 2. Quasi-static configuration signals (set once at dispatch, held constant during compute)
set_false_path -from [get_ports cfg_dataflow_mode*]
