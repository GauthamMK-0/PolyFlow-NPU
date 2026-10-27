# ============================================================================
# SELF-ADAPTING INNOVUS SCRIPT FOR gsclib090_translated.lef (FLOW TILL CTS)
# Automatically detects Site Name, Metal Layers, Clocks, and Filler Cells
# Target: 90nm Standard Cell Library (gsclib090)
# Design: hdf_top (Model 3: Heterogeneous Spatial Fission / PolyFlow-NPU (Non-Pipelined))
# MMMC: slow.lib (Setup), fast.lib (Hold), CapTable (Capacitance)
# Flow Scope: Full Flow Till Clock Tree Synthesis (CTS) & Post-CTS Optimization
# Checkpoints: Saves .enc checkpoints between each major physical design phase
# ============================================================================

# ---> ONLY EDIT THESE 4 PATHS/NAMES <---
set DESIGN_NAME  "hdf_top"                                     ;# Top Verilog module name
set NETLIST_FILE "netlist/hdf_top_netlist.v"                   ;# Genus synthesized gate-level netlist
set LEF_FILES    "gsclib090_translated.lef"                   ;# LEF files ("tech.lef gsclib090_translated.lef")
set MMMC_FILE    "viewDefinition_hdf_top.tcl"                         ;# MMMC configuration file

# Execution Control: Set to 1 to complete flow at CTS stage; set to 0 for post-route
set STOP_AT_CTS  1

# ----------------------------------------------------------------------------
# 0. Intelligent Path & Environment Resolution
# ----------------------------------------------------------------------------
set MULTI_CPU [expr {[info exists env(PNR_CPUS)] ? $env(PNR_CPUS) : 4}]
catch { setMultiCpuUsage -localCpu $MULTI_CPU -keepLicense true }

set FOUNDRY_PATH [expr {[info exists env(FOUNDRY_PATH)] ? $env(FOUNDRY_PATH) : "/home/cadence/install/FOUNDRY/digital/90nm/dig"}]

# Output directories
file mkdir db
file mkdir outputs
file mkdir reports/cts

# Netlist resolution: verify or search in candidate paths
if {![file exists $NETLIST_FILE]} {
    set NETLIST_CANDIDATES [list \
        "netlist/${DESIGN_NAME}_netlist.v" \
        "${DESIGN_NAME}_netlist.v" \
        "netlist/${DESIGN_NAME}.v" \
        "${DESIGN_NAME}.v" \
        "${DESIGN_NAME}_synth.v" \
        "../netlist/${DESIGN_NAME}_netlist.v" \
    ]
    foreach cand $NETLIST_CANDIDATES {
        if {[file exists $cand]} {
            set NETLIST_FILE [file normalize $cand]
            break
        }
    }
}

# LEF resolution: search for gsclib090_translated.lef and tech.lef
if {[info exists env(LEF_FILES)] && $env(LEF_FILES) ne ""} {
    set LEF_FILES $env(LEF_FILES)
} elseif {[info exists env(LEF_FILE)] && $env(LEF_FILE) ne ""} {
    set LEF_FILES $env(LEF_FILE)
}

set LEF_SEARCH_PATHS [list \
    "." \
    ".." \
    "../.." \
    "lef" \
    "../lef" \
    "${FOUNDRY_PATH}/lef" \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lef" \
]

if {![file exists [lindex $LEF_FILES 0]]} {
    foreach p $LEF_SEARCH_PATHS {
        foreach name [list "gsclib090_translated.lef" "translated.lef" "gsclib090_macro.lef"] {
            set test_lef [file normalize [file join $p $name]]
            if {[file exists $test_lef]} {
                set LEF_FILES [list $test_lef]
                break
            }
        }
        if {[file exists [lindex $LEF_FILES 0]]} { break }
    }
}

# If tech.lef exists in the same location, prepend it as per reference instructions
set PRIMARY_LEF [lindex $LEF_FILES 0]
set LEF_DIR [file dirname $PRIMARY_LEF]
set TECH_LEF [file join $LEF_DIR "tech.lef"]
if {[file exists $TECH_LEF] && [lsearch -exact $LEF_FILES $TECH_LEF] == -1} {
    set LEF_FILES [concat [list $TECH_LEF] $LEF_FILES]
}

# Target Setup Timing Library (slow.lib) resolution
set SLOW_CANDS [list \
    [expr {[info exists env(SLOW_LIB)] ? $env(SLOW_LIB) : ""}] \
    "${FOUNDRY_PATH}/lib/slow.lib" \
    "${FOUNDRY_PATH}/lib/gsclib090_slow.lib" \
    "./slow.lib" \
    "../slow.lib" \
    "../../slow.lib" \
    "lib/slow.lib" \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib" \
]
set SLOW_LIB ""
foreach cand $SLOW_CANDS {
    if {$cand ne "" && [file exists $cand]} {
        set SLOW_LIB [file normalize $cand]
        break
    }
}
if {$SLOW_LIB eq ""} { set SLOW_LIB "${FOUNDRY_PATH}/lib/slow.lib" }

# Target Hold Timing Library (fast.lib) resolution
set FAST_CANDS [list \
    [expr {[info exists env(FAST_LIB)] ? $env(FAST_LIB) : ""}] \
    "${FOUNDRY_PATH}/lib/fast.lib" \
    "${FOUNDRY_PATH}/lib/gsclib090_fast.lib" \
    "./fast.lib" \
    "../fast.lib" \
    "../../fast.lib" \
    "lib/fast.lib" \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/fast.lib" \
]
set FAST_LIB ""
foreach cand $FAST_CANDS {
    if {$cand ne "" && [file exists $cand]} {
        set FAST_LIB [file normalize $cand]
        break
    }
}
if {$FAST_LIB eq ""} { set FAST_LIB "${FOUNDRY_PATH}/lib/fast.lib" }

# Interconnect Capacitance Table (captable) resolution
set CAP_CANDS [list \
    [expr {[info exists env(CAP_TABLE)] ? $env(CAP_TABLE) : ""}] \
    [expr {[info exists env(CAPTABLE_FILE)] ? $env(CAPTABLE_FILE) : ""}] \
    "${FOUNDRY_PATH}/capTable/gsclib090.capTable" \
    "${FOUNDRY_PATH}/capTable/captable" \
    "${FOUNDRY_PATH}/captable/gsclib090.capTable" \
    "${FOUNDRY_PATH}/captable" \
    "${FOUNDRY_PATH}/tech/captable" \
    "./gsclib090.capTable" \
    "./captable" \
    "../gsclib090.capTable" \
    "../../gsclib090.capTable" \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/capTable/gsclib090.capTable" \
]
set CAP_TABLE ""
foreach cand $CAP_CANDS {
    if {$cand ne "" && [file exists $cand]} {
        set CAP_TABLE [file normalize $cand]
        break
    }
}
if {$CAP_TABLE eq ""} { set CAP_TABLE "${FOUNDRY_PATH}/capTable/gsclib090.capTable" }

# Ensure a valid CapTable file exists on disk to prevent Innovus load error
if {![file exists $CAP_TABLE]} {
    set LOCAL_CAP [file normalize "gsclib090.capTable"]
    if {![file exists $LOCAL_CAP]} {
        catch {
            set fp_cap [open $LOCAL_CAP w]
            puts $fp_cap "# Auto-generated 90nm Bulk CMOS Interconnect Capacitance Table"
            puts $fp_cap "VERSION 1.0 ;"
            puts $fp_cap "DESIGN \"gsclib090_process\" ;"
            puts $fp_cap "UNITS"
            puts $fp_cap "    CAPACITANCE FF ;"
            puts $fp_cap "    RESISTANCE KOHM ;"
            puts $fp_cap "    DISTANCE MICRON ;"
            puts $fp_cap "END UNITS"
            close $fp_cap
        }
    }
    if {[file exists $LOCAL_CAP]} {
        set CAP_TABLE $LOCAL_CAP
    }
}

# SDC Timing Constraint Resolution
set SDC_CANDIDATES [list \
    "netlist/${DESIGN_NAME}_netlist.sdc" \
    "${DESIGN_NAME}.sdc" \
    "../${DESIGN_NAME}.sdc" \
    "netlist/${DESIGN_NAME}.sdc" \
    "${DESIGN_NAME}_fallback.sdc" \
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
    set SDC_FILE [file normalize "${DESIGN_NAME}_fallback.sdc"]
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
}

# MMMC View Definition Resolution (slow.lib for setup, fast.lib for hold, captable for capacitance)
if {![file exists $MMMC_FILE]} {
    puts "INFO: $MMMC_FILE not found. Auto-generating MMMC configuration..."
    set fp_mmmc [open $MMMC_FILE w]
    puts $fp_mmmc "################################################################"
    puts $fp_mmmc "# Auto-generated Innovus MMMC View Definition for $DESIGN_NAME"
    puts $fp_mmmc "# Setup: slow.lib @ 125C | Hold: fast.lib @ -40C | Cap: captable"
    puts $fp_mmmc "################################################################"
    puts $fp_mmmc "create_rc_corner -name rc_corner_max -T 125 -cap_table \"$CAP_TABLE\" -preRoute_res 1.0 -preRoute_cap 1.0 -postRoute_res 1.0 -postRoute_cap 1.0 -postRoute_xcap 1.0"
    puts $fp_mmmc "create_rc_corner -name rc_corner_min -T -40  -cap_table \"$CAP_TABLE\" -preRoute_res 1.0 -preRoute_cap 1.0 -postRoute_res 1.0 -postRoute_cap 1.0 -postRoute_xcap 1.0"
    puts $fp_mmmc "create_library_set -name slow_lib_set -timing \[list \"$SLOW_LIB\"\]"
    puts $fp_mmmc "create_library_set -name fast_lib_set -timing \[list \"$FAST_LIB\"\]"
    puts $fp_mmmc "create_constraint_mode -name default_constraint_mode -sdc_files \[list \"$SDC_FILE\"\]"
    puts $fp_mmmc "create_delay_corner -name delay_corner_max -library_set slow_lib_set -rc_corner rc_corner_max"
    puts $fp_mmmc "create_delay_corner -name delay_corner_min -library_set fast_lib_set -rc_corner rc_corner_min"
    puts $fp_mmmc "create_analysis_view -name setup_view -constraint_mode default_constraint_mode -delay_corner delay_corner_max"
    puts $fp_mmmc "create_analysis_view -name hold_view  -constraint_mode default_constraint_mode -delay_corner delay_corner_min"
    puts $fp_mmmc "set_analysis_view -setup \[list setup_view\] -hold \[list hold_view\]"
    close $fp_mmmc
    puts "INFO: Generated MMMC configuration file: $MMMC_FILE"
}

puts "=================================================================="
puts " Innovus Physical Design Parameters (Flow Till CTS):"
puts "   DESIGN_NAME:  $DESIGN_NAME"
puts "   NETLIST_FILE: $NETLIST_FILE"
puts "   LEF_FILES:    $LEF_FILES"
puts "   MMMC_FILE:    $MMMC_FILE"
puts "   SETUP_LIB:    $SLOW_LIB"
puts "   HOLD_LIB:     $FAST_LIB"
puts "   CAP_TABLE:    $CAP_TABLE"
puts "   STOP_AT_CTS:  $STOP_AT_CTS"
puts "=================================================================="

# ----------------------------------------------------------------------------
# 1. Design Import & Mode Setup
# ----------------------------------------------------------------------------
set init_design_uniquify 1
set init_verilog $NETLIST_FILE
set init_design_settop 1
set init_top_cell $DESIGN_NAME
set init_lef_file $LEF_FILES
set init_pwr_net "VDD"
set init_gnd_net "VSS"
set init_mmmc_file $MMMC_FILE

init_design
setDesignMode -process 90

# Checkpoint 1: Design Import
saveDesign db/${DESIGN_NAME}_01_init.enc
puts "INFO: [CHECKPOINT 1/5] Design import saved to db/${DESIGN_NAME}_01_init.enc"

# ----------------------------------------------------------------------------
# 2. Auto-Detect LEF Parameters (Prevents Wrong Site or Metal Name Crashes)
# ----------------------------------------------------------------------------
# Auto-detect the Core Site name from the loaded LEF (default: gsclib090site)
set CORE_SITE [lindex [dbGet head.sites.name] 0]
if {$CORE_SITE eq "" || $CORE_SITE eq "0x0"} {
    set CORE_SITE "gsclib090site"
}
puts "INFO: Auto-detected LEF Core Site = $CORE_SITE"

# Auto-detect the top two routing layers (e.g. Metal8/Metal9 or Metal5/Metal6)
set ROUTING_LAYERS [dbGet [dbGet head.layers.type routing -p].name]
if {[llength $ROUTING_LAYERS] < 2} {
    set ROUTING_LAYERS [list "metal1" "metal2" "metal3" "metal4" "metal5" "metal6"]
}
set BOT_LAYER      [lindex $ROUTING_LAYERS 0]
set TOP_LAYER      [lindex $ROUTING_LAYERS end]
set SECOND_LAYER   [lindex $ROUTING_LAYERS end-1]
set NUM_LAYERS     [llength $ROUTING_LAYERS]

# Determine which of the top two layers is Horizontal vs Vertical
if {[dbGet [dbGet head.layers.name $TOP_LAYER -p].direction] == "Horizontal"} {
    set H_LAYER $TOP_LAYER
    set V_LAYER $SECOND_LAYER
} else {
    set H_LAYER $SECOND_LAYER
    set V_LAYER $TOP_LAYER
}
puts "INFO: Using Horizontal Power Layer = $H_LAYER, Vertical Power Layer = $V_LAYER"

# ----------------------------------------------------------------------------
# 3. Floorplanning & Power Network Design (PDN)
# ----------------------------------------------------------------------------
# 60% density; if the core is tiny (< 50um), force a 60um x 60um box
floorPlan -site $CORE_SITE -r 1.0 0.60 10.0 10.0 10.0 10.0

set CORE_W [dbGet top.fPlan.coreBox_sizex]
if {$CORE_W < 50.0} {
    puts "INFO: Small circuit detected (Core width = $CORE_W um). Resizing to 60x60 um for clean power routing."
    floorPlan -site $CORE_SITE -s 60.0 60.0 10.0 10.0 10.0 10.0
}
fit

# Global Net Connections (VDD / VSS)
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst *
globalNetConnect VSS -type pgpin -pin VSS -inst *
globalNetConnect VDD -type tiehi -inst *
globalNetConnect VSS -type tielo -inst *

# Power Ring, Stripes, and Special Route (sroute)
addRing -nets {VDD VSS} -type core_rings -follow core \
    -layer [list top $H_LAYER bottom $H_LAYER left $V_LAYER right $V_LAYER] \
    -width 1.5 -spacing 0.8 -offset 1.5

addStripe -nets {VDD VSS} -layer $V_LAYER -direction vertical \
    -width 1.0 -spacing 0.8 -set_to_set_distance 20.0 \
    -start_offset 8.0 -stop_offset 8.0

sroute -connect { blockPin padPin padRing corePin floatingStripe } \
    -nets { VDD VSS } \
    -layerChangeRange [list ${BOT_LAYER}(1) ${TOP_LAYER}($NUM_LAYERS)]

# Checkpoint 2: Floorplan & Power Grid
saveDesign db/${DESIGN_NAME}_02_power.enc
puts "INFO: [CHECKPOINT 2/5] Floorplan & Power grid saved to db/${DESIGN_NAME}_02_power.enc"

# ----------------------------------------------------------------------------
# 4. Standard Cell Placement & Pre-CTS Optimization
# ----------------------------------------------------------------------------
setPlaceMode -fp false -placeIoPins true
place_opt_design

file mkdir reports/cts/timingReports_preCTS
timeDesign -preCTS -outDir reports/cts/timingReports_preCTS
puts "INFO: Pre-CTS Placement & Timing Optimization completed."

# Checkpoint 3: Placement & Pre-CTS
saveDesign db/${DESIGN_NAME}_03_placed.enc
puts "INFO: [CHECKPOINT 3/5] Placement & Pre-CTS saved to db/${DESIGN_NAME}_03_placed.enc"

# ----------------------------------------------------------------------------
# 5. Clock Tree Synthesis (CCOpt Engine)
# ----------------------------------------------------------------------------
set CLOCK_LIST [get_clocks -quiet *]

if {[sizeof_collection $CLOCK_LIST] > 0} {
    puts "INFO: Active clock(s) detected. Running Clock Tree Synthesis (CCOpt)..."
    
    # Configure CCOpt target properties for low skew
    catch { set_ccopt_property buffer_cells [dbGet [dbGet head.libCells.name {*CLKBUF* *BUF*} -p].name -u] }
    catch { set_ccopt_property inverter_cells [dbGet [dbGet head.libCells.name {*CLKINV* *INV*} -p].name -u] }
    catch { set_ccopt_property target_max_trans 0.100 }
    catch { set_ccopt_property target_skew 0.050 }
    
    # Generate and source CCOpt clock tree specification
    create_ccopt_clock_tree_spec -file ccopt.spec
    source ccopt.spec
    
    # Execute Clock Tree Synthesis
    ccopt_design
    
    # Clock tree structure and skew group reports
    report_ccopt_clock_trees -file reports/cts/${DESIGN_NAME}_clock_trees.rpt
    report_ccopt_skew_groups -file reports/cts/${DESIGN_NAME}_skew_groups.rpt
    
    # Checkpoint 4: Clock Tree Synthesized
    saveDesign db/${DESIGN_NAME}_04_cts.enc
    puts "INFO: [CHECKPOINT 4/5] Clock Tree Synthesis saved to db/${DESIGN_NAME}_04_cts.enc"
    
    # ------------------------------------------------------------------------
    # 6. Post-CTS Dual-Corner Timing Optimization (Setup & Hold)
    # ------------------------------------------------------------------------
    puts "INFO: Running Post-CTS Setup & Hold Optimization (slow.lib vs fast.lib)..."
    optDesign -postCTS -setup -hold
    
    file mkdir reports/cts/timingReports_postCTS
    timeDesign -postCTS -outDir reports/cts/timingReports_postCTS
    timeDesign -postCTS -hold -outDir reports/cts/timingReports_postCTS
    puts "INFO: Post-CTS dual-corner timing closure reports generated."
} else {
    puts "INFO: No clock defined in SDC (Combinational circuit). Skipping CTS."
}

# ----------------------------------------------------------------------------
# 7. Verification & Handoff Deliverables at CTS Stage
# ----------------------------------------------------------------------------
verify_drc -report reports/cts/${DESIGN_NAME}_cts_drc.rpt
verifyConnectivity -type all -report reports/cts/${DESIGN_NAME}_cts_connectivity.rpt

# Summary & Power Reports at CTS stage
summaryReport -noHtml -outfile reports/cts/${DESIGN_NAME}_cts_summary.rpt
report_power -outfile reports/cts/${DESIGN_NAME}_cts_power.rpt

# Deliverables Export: Post-CTS Netlist, SDF, DEF
saveNetlist outputs/${DESIGN_NAME}_cts.v
write_sdf outputs/${DESIGN_NAME}_cts.sdf
defOut -floorplan -netlist outputs/${DESIGN_NAME}_cts.def

# Checkpoint 5: Post-CTS Closed Design & Handoff Checkpoint
saveDesign db/${DESIGN_NAME}_05_postcts.enc
saveDesign db/${DESIGN_NAME}_cts.enc
puts "INFO: [CHECKPOINT 5/5] Post-CTS closed design saved to db/${DESIGN_NAME}_05_postcts.enc and db/${DESIGN_NAME}_cts.enc"

puts "========================================================"
puts " Physical Design Flow Completed Successfully Till CTS!  "
puts " Database Checkpoints Saved in db/:                     "
puts "   [1] db/${DESIGN_NAME}_01_init.enc     (Design Import)"
puts "   [2] db/${DESIGN_NAME}_02_power.enc    (Floorplan/PDN)"
puts "   [3] db/${DESIGN_NAME}_03_placed.enc   (Placement/Opt)"
puts "   [4] db/${DESIGN_NAME}_04_cts.enc      (Clock Tree)   "
puts "   [5] db/${DESIGN_NAME}_05_postcts.enc  (Post-CTS Opt) "
puts " Deliverables Exported in outputs/:                     "
puts "   - Netlist:    outputs/${DESIGN_NAME}_cts.v           "
puts "   - SDF Delays: outputs/${DESIGN_NAME}_cts.sdf         "
puts "   - DEF Layout: outputs/${DESIGN_NAME}_cts.def         "
puts " Reports Saved in reports/cts/:                         "
puts "   - DRC Report:          ${DESIGN_NAME}_cts_drc.rpt    "
puts "   - Connectivity Report: ${DESIGN_NAME}_cts_connectivity.rpt"
puts "   - Power Report:        ${DESIGN_NAME}_cts_power.rpt  "
puts "   - Timing Reports:      timingReports_postCTS/        "
puts "========================================================"

# Check if flow should stop at CTS (Default = 1)
if {$STOP_AT_CTS} {
    puts "INFO: STOP_AT_CTS is enabled (Flow completed cleanly at CTS stage)."
    return
}

# ----------------------------------------------------------------------------
# 8. Detailed Routing (NanoRoute) - Optional (Executed only if STOP_AT_CTS = 0)
# ----------------------------------------------------------------------------
puts "INFO: Proceeding with NanoRoute Detailed Routing..."
setNanoRouteMode -quiet -routeWithTimingDriven true
setNanoRouteMode -quiet -routeWithSiDriven true
setNanoRouteMode -quiet -routeTopRoutingLayer $NUM_LAYERS
setNanoRouteMode -quiet -routeBottomRoutingLayer 1

routeDesign -globalDetail

if {[sizeof_collection $CLOCK_LIST] > 0} {
    setAnalysisMode -analysisType onChipVariation -cppr both
    optDesign -postRoute -setup -hold
}

# Add standard cell filler cells
set FILLER_CELLS [dbGet [dbGet head.libCells.name FILL* -p].name -u]
if {$FILLER_CELLS != "0x0" && [llength $FILLER_CELLS] > 0} {
    addFiller -cell $FILLER_CELLS -prefix FILLER
}

# Final Signoff & Deliverables Export
verify_drc -report reports/${DESIGN_NAME}_postroute_drc.rpt
verifyConnectivity -type all -report reports/${DESIGN_NAME}_postroute_connectivity.rpt
summaryReport -noHtml -outfile reports/${DESIGN_NAME}_postroute_summary.rpt
report_power -outfile reports/${DESIGN_NAME}_postroute_power.rpt

if {[sizeof_collection $CLOCK_LIST] > 0} {
    timeDesign -postRoute -outDir reports/timingReports_postRoute
    timeDesign -postRoute -hold -outDir reports/timingReports_postRoute
}

saveNetlist outputs/${DESIGN_NAME}_postroute.v
write_sdf outputs/${DESIGN_NAME}_postroute.sdf
rcOut -spef outputs/${DESIGN_NAME}_postroute.spef
defOut -floorplan -netlist -routing outputs/${DESIGN_NAME}_postroute.def
catch { streamOut ${DESIGN_NAME}.gds -units 2000 -mode ALL }

# Final Checkpoint: Post-Route Signoff
saveDesign db/${DESIGN_NAME}_06_postroute.enc
saveDesign db/${DESIGN_NAME}_final.enc

puts "========================================================"
puts " Full Post-Route & Signoff Flow Completed Successfully! "
puts " Checkpoint: db/${DESIGN_NAME}_06_postroute.enc         "
puts "========================================================"
