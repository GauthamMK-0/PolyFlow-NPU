# ==============================================================================
# Cadence Genus Synthesis TCL Script for HDF Top Module (Model 3: Heterogeneous Fission)
# ==============================================================================

# --- Design & Path Configurations ---
set_db use_scan_seqs_for_non_dft false
set_db init_lib_search_path {/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/}

# Target design directory
set_db init_hdl_search_path {./rtl}

# Read target technology library
read_libs slow.lib

# --- Read HDF RTL Files ---
# Order matters: sub-modules (PE, Decoder, Grid, Memory engines) before Top wrapper
read_hdl -sv {
    hdf_pe.sv
    hdf_fission_decoder.sv
    hdf_array_grid.sv
    eppa_arbiter.sv
    otp_token_fsm.sv
    pod_bank_scrub.sv
    hdf_top.sv
}

# --- Elaborate Top Level Design ---
elaborate hdf_top
init_design

# --- Load Timing Constraints ---
if {[file exists hdf_top.sdc]} {
    read_sdc hdf_top.sdc
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
report_timing > reports/timing_hdf.rpt
report_power  > reports/power_hdf.rpt
report_area   > reports/area_hdf.rpt
report_qor    > reports/qor_hdf.rpt

# --- Netlist & Gate-Level Files Generation ---
write_hdl > hdf_top_netlist.v
write_sdc > hdf_top_netlist.sdc
write_sdf -timescale ns -nonegchecks -recrem split -edges check_edge -setuphold split > hdf_top_netlist.sdf

puts "=================================================================="
puts " Genus Synthesis Finished Successfully! Check reports for details."
puts "=================================================================="
