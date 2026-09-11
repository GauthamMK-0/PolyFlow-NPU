# ==============================================================================
# Cadence Genus Synthesis TCL Script for DFS Top Module (Model 1)
# ==============================================================================

# --- Design & Path Configurations ---
set_db use_scan_seqs_for_non_dft false
set_db init_lib_search_path {/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/}

# Target design directory (relative to execution directory or absolute)
set_db init_hdl_search_path {./rtl}

# Read target technology library
read_libs slow.lib

# --- Read DFS RTL Files ---
# Order matters: Compile sub-modules (PE, Array) before the Top wrapper
read_hdl -sv {dfs_pe.sv dfs_array.sv dfs_top.sv}

# --- Elaborate Top Level Design ---
elaborate dfs_top
init_design

# --- Load Timing Constraints ---
if {[file exists dfs_top.sdc]} {
    read_sdc dfs_top.sdc
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
report_timing > reports/timing_dfs.rpt
report_power  > reports/power_dfs.rpt
report_area   > reports/area_dfs.rpt
report_qor    > reports/qor_dfs.rpt

# --- Netlist & Gate-Level Files Generation ---
write_hdl > dfs_top_netlist.v
write_sdc > dfs_top_netlist.sdc
write_sdf -timescale ns -nonegchecks -recrem split -edges check_edge -setuphold split > dfs_top_netlist.sdf

puts "=================================================================="
puts " Genus Synthesis Finished Successfully! Check reports for details."
puts "=================================================================="
