# ==============================================================================
# SDC Timing Constraints: hdf_top (Model 3: Heterogeneous Fission / PolyFlow-NPU)
# ==============================================================================

# Clock definition (1.0 ns period = 1.0 GHz target frequency)
create_clock -name clk -period 1.000 [get_ports clk]

# Clock uncertainty & transition
set_clock_uncertainty 0.05 [get_clocks clk]
set_clock_transition 0.05 [get_clocks clk]

# Input / Output Delays (20% clock period budget)
set_input_delay  0.200 -clock clk [all_inputs -no_clocks]
set_output_delay 0.200 -clock clk [all_outputs]

# Driving cell & load
set_driving_cell -lib_cell INVX1 [all_inputs -no_clocks]
set_load 0.010 [all_outputs]
