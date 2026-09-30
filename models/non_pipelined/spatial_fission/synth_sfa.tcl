# ==============================================================================
# Cadence Genus Synthesis TCL Script for SFA Top Module (Model 2: Spatial Fission)
# ==============================================================================

# --- Design & Path Configurations ---
set_db use_scan_seqs_for_non_dft false
set_db init_lib_search_path {/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/}

# Target design directory
set_db init_hdl_search_path {./rtl}

# Read target technology library
read_libs slow.lib

# --- Read SFA RTL Files ---
# Order matters: sub-modules (PE, Decoder, Array, Memory engines) before Top wrapper
read_hdl -sv {
    sfa_pe.sv
    sfa_fission_decoder.sv
    sfa_array.sv
    sfa_otp_fsm.sv
    sfa_bank_scrub.sv
    sfa_eppa.sv
    sfa_top.sv
}

# --- Elaborate Top Level Design ---
elaborate sfa_top
init_design

# --- Load Timing Constraints ---
if {[file exists sfa_top.sdc]} {
    read_sdc sfa_top.sdc
} else {
    # Default fallback: 1000 MHz / 1.0 ns clock on clk
    create_clock -name clk -period 1.0 [get_ports clk]
    set_input_delay  0.2 -clock clk [all_inputs -no_clocks]
    set_output_delay 0.2 -clock clk [all_outputs]
}

# --- Synthesis Effort Controls ---
set_db syn_generic_effort medium
set_db syn_map_effort medium
set_db syn_opt_effort medium

# --- Synthesis Execution ---
syn_generic
syn_map
syn_opt

# --- Timing, Power, and Area Reports ---
file mkdir reports
report_timing > reports/timing_sfa.rpt
report_power  > reports/power_sfa.rpt
report_area   > reports/area_sfa.rpt
report_qor    > reports/qor_sfa.rpt

# --- Netlist & Gate-Level Files Generation ---
write_hdl > sfa_top_netlist.v
write_sdc > sfa_top_netlist.sdc
write_sdf -timescale ns -nonegchecks -recrem split -edges check_edge -setuphold split > sfa_top_netlist.sdf

puts "=================================================================="
puts " Genus Synthesis Finished Successfully! Check reports for details."
puts "=================================================================="
