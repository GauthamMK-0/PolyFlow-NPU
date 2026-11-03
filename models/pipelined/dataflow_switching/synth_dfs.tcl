# ==============================================================================
# Cadence Genus Synthesis TCL Script for DFS Top (Model 1: Pipelined Variant)
# Supports Multi-Scale Synthesis: 4x4, 8x8, 16x16
# ==============================================================================

# --- Scale Configuration (4x4, 8x8, 16x16) ---
set SCALE [expr {[info exists env(SCALE)] ? $env(SCALE) : "4x4"}]
if {$SCALE eq "8x8"} {
    set NUM_ROWS 8
    set NUM_COLS 8
} elseif {$SCALE eq "16x16"} {
    set NUM_ROWS 16
    set NUM_COLS 16
} else {
    set SCALE "4x4"
    set NUM_ROWS 4
    set NUM_COLS 4
}

puts "=================================================================="
puts " \[GENUS SYNTHESIS\] Target: dfs_top | Scale: ${SCALE} (${NUM_ROWS}x${NUM_COLS})"
puts "=================================================================="

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
if {$SCALE eq "4x4"} {
    elaborate dfs_top
} else {
    elaborate dfs_top -parameters [list [list NUM_ROWS $NUM_ROWS] [list NUM_COLS $NUM_COLS]]
}
init_design

# --- Load Timing Constraints ---
if {[file exists dfs_top_${SCALE}.sdc]} {
    read_sdc dfs_top_${SCALE}.sdc
} elseif {[file exists dfs_top.sdc]} {
    read_sdc dfs_top.sdc
} else {
    # Default fallback: 200 MHz / 5.000 ns clock on clk
    create_clock -name clk -period 5.000 [get_ports clk]
    set_clock_uncertainty 0.050 [get_clocks clk]
    set_clock_transition  0.050 [get_clocks clk]
    set_input_delay  0.500 -clock clk [all_inputs -no_clocks]
    set_output_delay 0.500 -clock clk [all_outputs]
    set_driving_cell -lib_cell INVX1 [all_inputs -no_clocks]
    set_load 0.010 [all_outputs]
}

# --- Synthesis Effort Controls ---
set_db syn_generic_effort medium
set_db syn_map_effort medium
set_db syn_opt_effort medium

# --- Synthesis Execution ---
syn_generic
syn_map
syn_opt

# --- Timing, Power, Area, and Summary Reports ---
set REPORT_DIR "reports/${SCALE}"
file mkdir $REPORT_DIR
report_timing  > ${REPORT_DIR}/timing_dfs.rpt
report_power   > ${REPORT_DIR}/power_dfs.rpt
report_area    > ${REPORT_DIR}/area_dfs.rpt
report_qor     > ${REPORT_DIR}/qor_dfs.rpt
report_gates   > ${REPORT_DIR}/gates_dfs.rpt

# Backward compatibility mirror for 4x4
if {$SCALE eq "4x4"} {
    file mkdir reports
    catch { file copy -force ${REPORT_DIR}/timing_dfs.rpt reports/timing_dfs.rpt }
    catch { file copy -force ${REPORT_DIR}/power_dfs.rpt reports/power_dfs.rpt }
    catch { file copy -force ${REPORT_DIR}/area_dfs.rpt reports/area_dfs.rpt }
    catch { file copy -force ${REPORT_DIR}/qor_dfs.rpt reports/qor_dfs.rpt }
    catch { file copy -force ${REPORT_DIR}/gates_dfs.rpt reports/gates_dfs.rpt }
}

# --- Netlist & Gate-Level Files Generation ---
set NETLIST_DIR "netlist/${SCALE}"
file mkdir $NETLIST_DIR
write_hdl > ${NETLIST_DIR}/dfs_top_netlist.v
write_sdc > ${NETLIST_DIR}/dfs_top_netlist.sdc
write_sdf -timescale ns -nonegchecks -recrem split -edges check_edge -setuphold split > ${NETLIST_DIR}/dfs_top_netlist.sdf

# Backward compatibility mirror for 4x4
if {$SCALE eq "4x4"} {
    file mkdir netlist
    catch { file copy -force ${NETLIST_DIR}/dfs_top_netlist.v netlist/dfs_top_netlist.v }
    catch { file copy -force ${NETLIST_DIR}/dfs_top_netlist.sdc netlist/dfs_top_netlist.sdc }
    catch { file copy -force ${NETLIST_DIR}/dfs_top_netlist.sdf netlist/dfs_top_netlist.sdf }
}

puts "=================================================================="
puts " \[SYNTHESIS EXECUTIVE SUMMARY: dfs_top @ 200 MHz | Scale: ${SCALE}\]"
puts "=================================================================="
report_qor
report_area
report_timing
puts "=================================================================="
puts " Genus Synthesis Finished Successfully! Check ${REPORT_DIR}/ and ${NETLIST_DIR}/ for details."
puts "=================================================================="
