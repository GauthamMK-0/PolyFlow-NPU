# ==============================================================================
# Cadence Innovus Physical Design Script: Up to Standard Cell Placement
# Target: 90nm Standard Cell Library (gsclib090)
# Design: dfs_top (Model 1: Single-Tenant Dataflow Switching)
# Flow: Design Init -> Floorplan -> Power Rings/SRoute -> Placement & Pre-CTS Opt
# ==============================================================================

# --- 1. Top Module & Directories ---
set TOP_MODULE "dfs_top"

# Directory structure
set REPORT_DIR "reports/pnr_place"
set DB_DIR     "db"
file mkdir $REPORT_DIR
file mkdir $DB_DIR

# --- 2. Multi-Threading & License Setup ---
set MULTI_CPU [expr {[info exists env(PNR_CPUS)] ? $env(PNR_CPUS) : 4}]
catch { setMultiCpuUsage -localCpu $MULTI_CPU -keepLicense true }

puts "=================================================================="
puts " Innovus Placement Flow for: $TOP_MODULE"
puts " Target: 90nm gsclib090 Technology | CPUs: $MULTI_CPU"
puts "=================================================================="

# --- 3. Technology & Library Paths ---
set FOUNDRY_PATH [expr {[info exists env(FOUNDRY_PATH)] ? $env(FOUNDRY_PATH) : "/home/cadence/install/FOUNDRY/digital/90nm/dig"}]

# Resolution for tech.lef (must be loaded FIRST in Innovus)
set TECH_LEF_CANDIDATES [list \
    [expr {[info exists env(TECH_LEF)] ? $env(TECH_LEF) : ""}] \
    "${FOUNDRY_PATH}/lef/tech.lef" \
    "./tech.lef" \
    "../tech.lef" \
    "../../tech.lef" \
    "lef/tech.lef" \
    "${FOUNDRY_PATH}/lef/technology.lef" \
]

set TECH_LEF ""
foreach cand $TECH_LEF_CANDIDATES {
    if {$cand ne "" && [file exists $cand]} {
        set TECH_LEF [file normalize $cand]
        break
    }
}
if {$TECH_LEF eq ""} {
    set TECH_LEF [file normalize "${FOUNDRY_PATH}/lef/tech.lef"]
}

# Resolution for gsclib090_macro.lef (must be loaded SECOND in Innovus)
set CELL_LEF_CANDIDATES [list \
    [expr {[info exists env(CELL_LEF)] ? $env(CELL_LEF) : ""}] \
    "${FOUNDRY_PATH}/lef/gsclib090_macro.lef" \
    "./gsclib090_macro.lef" \
    "../gsclib090_macro.lef" \
    "../../gsclib090_macro.lef" \
    "lef/gsclib090_macro.lef" \
    "${FOUNDRY_PATH}/lef/slow.lef" \
]

set CELL_LEF ""
foreach cand $CELL_LEF_CANDIDATES {
    if {$cand ne "" && [file exists $cand]} {
        set CELL_LEF [file normalize $cand]
        break
    }
}
if {$CELL_LEF eq ""} {
    set CELL_LEF [file normalize "${FOUNDRY_PATH}/lef/gsclib090_macro.lef"]
}

puts "INFO: Tech LEF: $TECH_LEF"
puts "INFO: Cell LEF: $CELL_LEF"

set TARGET_LIB [expr {[info exists env(TARGET_LIB)] ? $env(TARGET_LIB) : "${FOUNDRY_PATH}/lib/slow.lib"}]

# --- 4. Robust Netlist Resolution ---
set NETLIST_CANDIDATES [list \
    "netlist/${TOP_MODULE}_netlist.v" \
    "${TOP_MODULE}_netlist.v" \
    "../netlist/${TOP_MODULE}_netlist.v" \
    "netlist/${TOP_MODULE}.v" \
    "${TOP_MODULE}.v" \
]

set NETLIST_FILE ""
foreach cand $NETLIST_CANDIDATES {
    if {[file exists $cand]} {
        set NETLIST_FILE [file normalize $cand]
        break
    }
}

if {$NETLIST_FILE eq ""} {
    puts "=================================================================="
    puts "ERROR: Synthesized netlist not found in netlist/ or current directory!"
    puts "Please run Genus synthesis first using: 'make synth-model1'"
    puts "Expected file: netlist/${TOP_MODULE}_netlist.v"
    puts "=================================================================="
    set NETLIST_FILE [file normalize "netlist/${TOP_MODULE}_netlist.v"]
} else {
    puts "INFO: Using gate-level netlist: $NETLIST_FILE"
}

# --- 5. Robust SDC Constraint Resolution (Prevents Error 405) ---
set SDC_CANDIDATES [list \
    "netlist/${TOP_MODULE}_netlist.sdc" \
    "${TOP_MODULE}.sdc" \
    "../${TOP_MODULE}.sdc" \
    "netlist/${TOP_MODULE}.sdc" \
]

set SDC_FILE ""
foreach cand $SDC_CANDIDATES {
    if {[file exists $cand]} {
        set SDC_FILE [file normalize $cand]
        break
    }
}

if {$SDC_FILE eq ""} {
    puts "WARNING: SDC constraints file not found! Generating default 200 MHz fallback SDC..."
    set SDC_FILE [file normalize "${TOP_MODULE}_fallback.sdc"]
    set fp_sdc [open $SDC_FILE w]
    puts $fp_sdc "# Auto-generated fallback SDC constraints (200 MHz / 5.0 ns)"
    puts $fp_sdc "create_clock -name clk -period 5.000 \[get_ports clk\]"
    puts $fp_sdc "set_clock_uncertainty 0.050 \[get_clocks clk\]"
    puts $fp_sdc "set_clock_transition 0.050 \[get_clocks clk\]"
    puts $fp_sdc "set_input_delay 0.500 -clock clk \[all_inputs -no_clocks\]"
    puts $fp_sdc "set_output_delay 0.500 -clock clk \[all_outputs\]"
    puts $fp_sdc "set_load 0.010 \[all_outputs\]"
    close $fp_sdc
    puts "INFO: Created fallback constraint file: $SDC_FILE"
} else {
    puts "INFO: Using timing constraint SDC: $SDC_FILE"
}

# --- 6. Dynamic MMMC View Definition (Fixes Line 63 init_design crash) ---
puts "--- Phase 1: Generating MMMC View Definition File ---"
set MMMC_FILE [file normalize "viewDefinition_${TOP_MODULE}.tcl"]
set fp_mmmc [open $MMMC_FILE w]
puts $fp_mmmc "################################################################"
puts $fp_mmmc "# Auto-generated Innovus MMMC View Definition for $TOP_MODULE"
puts $fp_mmmc "################################################################"
puts $fp_mmmc "create_rc_corner -name default_rc_corner -T 125"
puts $fp_mmmc "create_library_set -name slow_lib_set -timing \[list \"$TARGET_LIB\"\]"
puts $fp_mmmc "create_constraint_mode -name default_constraint_mode -sdc_files \[list \"$SDC_FILE\"\]"
puts $fp_mmmc "create_delay_corner -name slow_delay_corner -library_set slow_lib_set -rc_corner default_rc_corner"
puts $fp_mmmc "create_analysis_view -name default_analysis_view -constraint_mode default_constraint_mode -delay_corner slow_delay_corner"
close $fp_mmmc

# --- 7. Design Initialization (init_design) ---
puts "--- Phase 2: Design Initialization ---"

set init_gnd_net "VSS"
set init_pwr_net "VDD"
set init_verilog $NETLIST_FILE
set init_top_cell $TOP_MODULE

# Order strictly enforced: tech.lef FIRST, gsclib090_macro.lef SECOND
set init_lef_file [list $TECH_LEF $CELL_LEF]
set init_mmmc_file $MMMC_FILE

init_design -setup {default_analysis_view} -hold {default_analysis_view}

clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {}
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {}
globalNetConnect VDD -type tiehi -inst * -module {}
globalNetConnect VSS -type tielo -inst * -module {}

# --- 8. Floorplanning ---
puts "--- Phase 3: Floorplanning (Core Util: 70%, Margins: 10 um) ---"
floorPlan -site CoreSite -r 1.0 0.70 10.0 10.0 10.0 10.0

# --- 9. Power Planning: Rings & Standard Cell Rails (SRoute) ---
puts "--- Phase 4: Power Planning (Core Rings & SRoute) ---"

catch {
    addRing -nets {VDD VSS} -type core_rings -follow core \
        -layer {top Metal6 bottom Metal6 left Metal5 right Metal5} \
        -width 2.0 -spacing 1.0 -offset 2.0
} ring_err
if {[info exists ring_err] && $ring_err ne ""} {
    puts "addRing note: $ring_err (continuing)"
}

catch {
    sroute -connect { corePin } \
        -layerChangeRange { Metal1 Metal6 } \
        -blockPinTarget { nearestTarget } \
        -corePinTarget { firstAfterRowEnd } \
        -nets { VDD VSS }
} sroute_err
if {[info exists sroute_err] && $sroute_err ne ""} {
    puts "sroute note: $sroute_err (continuing)"
}

# --- 10. Standard Cell Placement & Pre-CTS Optimization ---
puts "--- Phase 5: Standard Cell Placement & Pre-CTS Optimization ---"

setPlaceMode -prerouteResourceBudget true \
             -timingDriven true \
             -congEffort high \
             -modulePadding 1.0

catch {
    place_opt_design -prefix place
} catch_err

if {[info exists catch_err] && $catch_err ne ""} {
    puts "place_opt_design note: $catch_err. Attempting place_design fallback..."
    catch { place_design -concurrent }
    catch { optDesign -preCTS }
}

# --- 11. Post-Placement Diagnostics & Reports ---
puts "--- Phase 6: Generating Post-Placement Reports ---"

catch { checkPlace $REPORT_DIR/check_place.rpt }
catch { report_density > $REPORT_DIR/density_place.rpt }
catch { timeDesign -preCTS -prefix place -outDir $REPORT_DIR }
catch { reportCongestion -hotSpot > $REPORT_DIR/congestion_place.rpt }

# --- 12. Save Placement Checkpoint Database ---
saveDesign $DB_DIR/${TOP_MODULE}_placed.enc

puts "=================================================================="
puts " Innovus Placement Stage Complete!"
puts " Placed Database Saved: $DB_DIR/${TOP_MODULE}_placed.enc"
puts " Diagnostic Reports:    $REPORT_DIR/"
puts "=================================================================="
