# ==============================================================================
# SDC Timing Constraints: sfa_top (Model 2: Spatial Fission)
# Target Operating Frequency: 200 MHz (Clock Period = 5.000 ns)
# ==============================================================================

# Clock definition (5.000 ns = 200 MHz target frequency)
create_clock -name clk -period 5.000 [get_ports clk]

# Clock uncertainty & transition
set_clock_uncertainty 0.050 [get_clocks clk]
set_clock_transition  0.050 [get_clocks clk]

# Input / Output Delays (10% clock period budget)
set_input_delay  0.500 -clock clk [all_inputs -no_clocks]
set_output_delay 0.500 -clock clk [all_outputs]

# Driving cell & load
set_driving_cell -lib_cell INVX1 [all_inputs -no_clocks]
set_load 0.010 [all_outputs]


