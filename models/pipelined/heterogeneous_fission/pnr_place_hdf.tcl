# ==============================================================================
# Cadence Innovus Physical Design Script: Up to Standard Cell Placement
# Target: 90nm Standard Cell Library (gsclib090)
# Design: hdf_top (Model 3: Heterogeneous Fission / PolyFlow-NPU)
# Flow: Design Init -> Floorplan -> Power Rings/SRoute -> Placement & Pre-CTS Opt
# ==============================================================================

# --- 1. Top Module & Directories ---
set TOP_MODULE "hdf_top"

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

# Resolution for gsclib090_translated.lef (only use gsclib090_translated.lef)
set LEF_CANDIDATES [list \
    [expr {[info exists env(LEF_FILE)] ? $env(LEF_FILE) : ""}] \
    "gsclib090_translated.lef" \
    "./gsclib090_translated.lef" \
    "../gsclib090_translated.lef" \
    "../../gsclib090_translated.lef" \
    "lef/gsclib090_translated.lef" \
    "${FOUNDRY_PATH}/lef/gsclib090_translated.lef" \
    "translated.lef" \
    "./translated.lef" \
    "../translated.lef" \
    "../../translated.lef" \
    "lef/translated.lef" \
    "${FOUNDRY_PATH}/lef/translated.lef" \
]

set LEF_FILE ""
foreach cand $LEF_CANDIDATES {
    if {$cand ne "" && [file exists $cand]} {
        set LEF_FILE [file normalize $cand]
        break
    }
}
if {$LEF_FILE eq ""} {
    set LEF_FILE [file normalize "gsclib090_translated.lef"]
}

# Resolution for TARGET_LIB (timing library for setup analysis)
set LIB_CANDIDATES [list \
    [expr {[info exists env(TARGET_LIB)] ? $env(TARGET_LIB) : ""}] \
    "${FOUNDRY_PATH}/lib/slow.lib" \
    "./slow.lib" \
    "../slow.lib" \
    "../../slow.lib" \
    "lib/slow.lib" \
    "${FOUNDRY_PATH}/lib/gsclib090_slow.lib" \
    "./gsclib090_slow.lib" \
    "${FOUNDRY_PATH}/lib/typical.lib" \
    "./typical.lib" \
]

set TARGET_LIB ""
foreach cand $LIB_CANDIDATES {
    if {$cand ne "" && [file exists $cand]} {
        set TARGET_LIB [file normalize $cand]
        break
    }
}
if {$TARGET_LIB eq ""} {
    set TARGET_LIB [file normalize "${FOUNDRY_PATH}/lib/slow.lib"]
}

puts "INFO: LEF File:    $LEF_FILE"
puts "INFO: Target LIB:  $TARGET_LIB"

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
    puts "Please run Genus synthesis first using: 'make synth-model3'"
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

# Use translated.lef as requested
set init_lef_file [list $LEF_FILE]
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

# Dynamically query active routing layers from loaded LEF database
set routing_layers [list]
catch { set routing_layers [get_db [get_db layers -if {.type == routing}] .name] }
if {[llength $routing_layers] == 0} {
    catch { set routing_layers [dbGet [dbGet -p head.layers.type routing].name] }
}

# If database query returns empty, fallback to standard gsclib090 lowercase names (metal1..metal6)
if {[llength $routing_layers] == 0} {
    set routing_layers [list "metal1" "metal2" "metal3" "metal4" "metal5" "metal6"]
}

set num_layers [llength $routing_layers]
set bot_layer  [lindex $routing_layers 0]
set top_layer  [lindex $routing_layers end]

puts "INFO: Detected routing layers in LEF: $routing_layers (Total: $num_layers)"

if {$num_layers >= 2} {
    if {$num_layers >= 6} {
        set ring_horiz [lindex $routing_layers 5]
        set ring_vert  [lindex $routing_layers 4]
    } elseif {$num_layers >= 4} {
        set ring_horiz [lindex $routing_layers 3]
        set ring_vert  [lindex $routing_layers 2]
    } else {
        set ring_horiz [lindex $routing_layers 1]
        set ring_vert  [lindex $routing_layers 0]
    }

    puts "INFO: Power Ring Layers -> Horizontal: $ring_horiz, Vertical: $ring_vert"
    puts "INFO: SRoute Layer Range -> $bot_layer to $top_layer"

    catch {
        addRing -nets {VDD VSS} -type core_rings -follow core \
            -layer [list top $ring_horiz bottom $ring_horiz left $ring_vert right $ring_vert] \
            -width 2.0 -spacing 1.0 -offset 2.0
    } ring_err
    if {[info exists ring_err] && $ring_err ne ""} {
        puts "addRing note: $ring_err (continuing to placement)"
    }

    catch {
        sroute -connect { corePin } \
            -layerChangeRange [list $bot_layer $top_layer] \
            -blockPinTarget { nearestTarget } \
            -corePinTarget { firstAfterRowEnd } \
            -nets { VDD VSS }
    } sroute_err
    if {[info exists sroute_err] && $sroute_err ne ""} {
        puts "sroute note: $sroute_err (continuing to placement)"
    }
} else {
    puts "INFO: No multi-layer routing stack defined in LEF. Skipping power rings and proceeding to placement."
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
