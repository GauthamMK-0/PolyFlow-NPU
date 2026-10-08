# ==============================================================================
# Cadence Genus Synthesis TCL Script for HDF Top (Model 3: Pipelined Variant)
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

# --- Force Array Flattening for Global Datapath Optimization ---
set_db auto_ungroup both
catch { ungroup -all -flatten }

# --- Load Timing Constraints ---
if {[file exists hdf_top.sdc]} {
    read_sdc hdf_top.sdc
    # Explicitly enforce multicycle path on reconfiguration registers
    catch { set_multicycle_path 2 -setup -from [get_cells -hier *region_id_mask*] }
    catch { set_multicycle_path 1 -hold  -from [get_cells -hier *region_id_mask*] }
} else {
    # Default fallback: 300 MHz / 3.333 ns clock on clk
    create_clock -name clk -period 3.333 [get_ports clk]
    set_input_delay  0.350 -clock clk [all_inputs -no_clocks]
    set_output_delay 0.350 -clock clk [all_outputs]
    set_false_path -from [get_ports rst_n]
    set_false_path -from [get_ports cfg_split_col*]
    set_false_path -from [get_ports cfg_update_strobe]
    set_false_path -from [get_ports dataflow_mode*]
    set_false_path -from [get_ports phase_tag*]
    set_false_path -from [get_ports role_reassign*]
    set_false_path -from [get_ports new_region_id_per_bank*]
    set_false_path -from [get_ports new_role_per_bank*]
    set_false_path -from [get_ports lifetime_init*]
    catch { set_multicycle_path 2 -setup -from [get_cells -hier *region_id_mask*] }
    catch { set_multicycle_path 1 -hold  -from [get_cells -hier *region_id_mask*] }
}

# --- Synthesis Effort Controls ---
set_db syn_generic_effort high
set_db syn_map_effort high
set_db syn_opt_effort high
set_db dp_analytical_opt extreme
set_db dp_sharing advanced

# --- Synthesis Execution ---
syn_generic
syn_map
syn_opt

# --- Timing, Power, Area, and Summary Reports ---
file mkdir reports
report_timing  > reports/timing_hdf.rpt
report_power   > reports/power_hdf.rpt
report_area    > reports/area_hdf.rpt
report_qor     > reports/qor_hdf.rpt
report_gates   > reports/gates_hdf.rpt
catch { report_summary > reports/summary_hdf.rpt }

# --- Netlist & Gate-Level Files Generation ---
file mkdir netlist
write_hdl > netlist/hdf_top_netlist.v
write_sdc > netlist/hdf_top_netlist.sdc
write_sdf -timescale ns -nonegchecks -recrem split -edges check_edge -setuphold split > netlist/hdf_top_netlist.sdf

puts "=================================================================="
puts " [SYNTHESIS EXECUTIVE SUMMARY: hdf_top @ 300 MHz]"
puts "=================================================================="
report_qor
report_area
puts "=================================================================="
puts " Genus Synthesis Finished Successfully! Check reports/ and netlist/ for details."
puts "=================================================================="
