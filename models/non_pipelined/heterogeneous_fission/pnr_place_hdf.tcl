# ============================================================================
# SELF-ADAPTING INNOVUS SCRIPT FOR gsclib090_translated.lef
# Automatically detects Site Name, Metal Layers, Clocks, and Filler Cells
# Target: 90nm Standard Cell Library (gsclib090)
# Design: hdf_top (Model 3: Heterogeneous Spatial Fission / PolyFlow-NPU)
# ============================================================================

# ---> ONLY EDIT THESE 4 PATHS/NAMES <---
set DESIGN_NAME  "hdf_top"                                     ;# Your top Verilog module name
set NETLIST_FILE "netlist/hdf_top_netlist.v"                   ;# Your Genus synthesized netlist
set LEF_FILES    "gsclib090_translated.lef"                   ;# If you have tech.lef, put it first: "tech.lef gsclib090_translated.lef"
set MMMC_FILE    "viewDefinition_hdf_top.tcl"                 ;# Your MMMC file

# ----------------------------------------------------------------------------
# 0. Intelligent Path & Environment Resolution
# ----------------------------------------------------------------------------
set MULTI_CPU [expr {[info exists env(PNR_CPUS)] ? $env(PNR_CPUS) : 4}]
catch { setMultiCpuUsage -localCpu $MULTI_CPU -keepLicense true }

set FOUNDRY_PATH [expr {[info exists env(FOUNDRY_PATH)] ? $env(FOUNDRY_PATH) : "/home/cadence/install/FOUNDRY/digital/90nm/dig"}]

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
                set LEF_FILES $test_lef
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

# Target Timing Library (slow.lib) resolution
set LIB_CANDIDATES [list \
    [expr {[info exists env(TARGET_LIB)] ? $env(TARGET_LIB) : ""}] \
    "${FOUNDRY_PATH}/lib/slow.lib" \
    "./slow.lib" \
    "../slow.lib" \
    "../../slow.lib" \
    "lib/slow.lib" \
    "${FOUNDRY_PATH}/lib/gsclib090_slow.lib" \
    "./gsclib090_slow.lib" \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib" \
]
set TARGET_LIB ""
foreach cand $LIB_CANDIDATES {
    if {$cand ne "" && [file exists $cand]} {
        set TARGET_LIB [file normalize $cand]
        break
    }
}
if {$TARGET_LIB eq ""} {
    set TARGET_LIB "slow.lib"
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

# MMMC View Definition Resolution
if {![file exists $MMMC_FILE]} {
    puts "INFO: $MMMC_FILE not found. Auto-generating MMMC view definition..."
    set fp_mmmc [open $MMMC_FILE w]
    puts $fp_mmmc "################################################################"
    puts $fp_mmmc "# Auto-generated Innovus MMMC View Definition for $DESIGN_NAME"
    puts $fp_mmmc "################################################################"
    puts $fp_mmmc "create_rc_corner -name default_rc_corner -T 125"
    puts $fp_mmmc "create_library_set -name slow_lib_set -timing \[list \"$TARGET_LIB\"\]"
    puts $fp_mmmc "create_constraint_mode -name default_constraint_mode -sdc_files \[list \"$SDC_FILE\"\]"
    puts $fp_mmmc "create_delay_corner -name slow_delay_corner -library_set slow_lib_set -rc_corner default_rc_corner"
    puts $fp_mmmc "create_analysis_view -name default_analysis_view -constraint_mode default_constraint_mode -delay_corner slow_delay_corner"
    close $fp_mmmc
    puts "INFO: Generated MMMC file: $MMMC_FILE"
}

puts "=================================================================="
puts " Innovus Physical Design Parameters:"
puts "   DESIGN_NAME:  $DESIGN_NAME"
puts "   NETLIST_FILE: $NETLIST_FILE"
puts "   LEF_FILES:    $LEF_FILES"
puts "   MMMC_FILE:    $MMMC_FILE"
puts "=================================================================="

# ----------------------------------------------------------------------------
# 1. Design Import
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

# ----------------------------------------------------------------------------
# 2. Auto-Detect LEF Parameters (Prevents Wrong Site or Metal Name Crashes)
# ----------------------------------------------------------------------------
# Auto-detect the Core Site name from the loaded LEF
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
# 3. Floorplanning (Safe for both Tiny and Large Circuits)
# ----------------------------------------------------------------------------
# First try 60% density; if the core is tiny (< 50um), force a 60um x 60um box
# so power rings and stripes always have room to route without DRC shorts.
floorPlan -site $CORE_SITE -r 1.0 0.60 10.0 10.0 10.0 10.0

set CORE_W [dbGet top.fPlan.coreBox_sizex]
if {$CORE_W < 50.0} {
    puts "INFO: Small circuit detected (Core width = $CORE_W um). Resizing to 60x60 um for clean power routing."
    floorPlan -site $CORE_SITE -s 60.0 60.0 10.0 10.0 10.0 10.0
}
fit

# ----------------------------------------------------------------------------
# 4. Global Net Connections (VDD / VSS)
# ----------------------------------------------------------------------------
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst *
globalNetConnect VSS -type pgpin -pin VSS -inst *
globalNetConnect VDD -type tiehi -inst *
globalNetConnect VSS -type tielo -inst *

# ----------------------------------------------------------------------------
# 5. Power Ring, Stripes, and Special Route (sroute)
# ----------------------------------------------------------------------------
addRing -nets {VDD VSS} -type core_rings -follow core \
    -layer [list top $H_LAYER bottom $H_LAYER left $V_LAYER right $V_LAYER] \
    -width 1.5 -spacing 0.8 -offset 1.5

addStripe -nets {VDD VSS} -layer $V_LAYER -direction vertical \
    -width 1.0 -spacing 0.8 -set_to_set_distance 20.0 \
    -start_offset 8.0 -stop_offset 8.0

sroute -connect { blockPin padPin padRing corePin floatingStripe } \
    -nets { VDD VSS } \
    -layerChangeRange [list ${BOT_LAYER}(1) ${TOP_LAYER}($NUM_LAYERS)]

# ----------------------------------------------------------------------------
# 6. Placement & Pre-CTS Optimization
# ----------------------------------------------------------------------------
# Place standard cells and automatically assign IO pins
setPlaceMode -fp false -placeIoPins true
place_opt_design

# ----------------------------------------------------------------------------
# 7. Clock Tree Synthesis (Auto-Skips if Circuit is Purely Combinational!)
# ----------------------------------------------------------------------------
set CLOCK_LIST [get_clocks -quiet *]

if {[sizeof_collection $CLOCK_LIST] > 0} {
    puts "INFO: Clock detected. Running Clock Tree Synthesis (CCOpt)..."
    create_ccopt_clock_tree_spec -file ccopt.spec
    source ccopt.spec
    ccopt_design
    optDesign -postCTS -setup -hold
} else {
    puts "INFO: No clock defined in SDC (Combinational circuit). Skipping CTS."
}

# ----------------------------------------------------------------------------
# 8. Detailed Routing (NanoRoute)
# ----------------------------------------------------------------------------
setNanoRouteMode -quiet -routeWithTimingDriven true
setNanoRouteMode -quiet -routeWithSiDriven true
setNanoRouteMode -quiet -routeTopRoutingLayer $NUM_LAYERS
setNanoRouteMode -quiet -routeBottomRoutingLayer 1

routeDesign -globalDetail

# Post-Route Timing Optimization (Only runs if timing constraints/clocks exist)
if {[sizeof_collection $CLOCK_LIST] > 0} {
    setAnalysisMode -analysisType onChipVariation -cppr both
    optDesign -postRoute -setup -hold
}

# ----------------------------------------------------------------------------
# 9. Add Standard Cell Fillers (Auto-Detects Filler Cells from LEF)
# ----------------------------------------------------------------------------
set FILLER_CELLS [dbGet [dbGet head.libCells.name FILL* -p].name -u]
if {$FILLER_CELLS != "0x0" && [llength $FILLER_CELLS] > 0} {
    addFiller -cell $FILLER_CELLS -prefix FILLER
}

# ----------------------------------------------------------------------------
# 10. Verification & Deliverables Export
# ----------------------------------------------------------------------------
file mkdir reports/pnr
file mkdir outputs
file mkdir db

verify_drc -report ${DESIGN_NAME}_drc.rpt
catch { file copy -force ${DESIGN_NAME}_drc.rpt reports/pnr/ }
verifyConnectivity -type all -report ${DESIGN_NAME}_connectivity.rpt
catch { file copy -force ${DESIGN_NAME}_connectivity.rpt reports/pnr/ }

# Reports
summaryReport -noHtml -outfile ${DESIGN_NAME}_summary.rpt
catch { file copy -force ${DESIGN_NAME}_summary.rpt reports/pnr/ }
report_power -outfile ${DESIGN_NAME}_power.rpt
catch { file copy -force ${DESIGN_NAME}_power.rpt reports/pnr/ }

if {[sizeof_collection $CLOCK_LIST] > 0} {
    timeDesign -postRoute -outDir timingReports
    timeDesign -postRoute -hold -outDir timingReports
    catch { file copy -force timingReports reports/pnr/ }
}

# Outputs
saveNetlist ${DESIGN_NAME}_postroute.v
catch { file copy -force ${DESIGN_NAME}_postroute.v outputs/ }
write_sdf ${DESIGN_NAME}_postroute.sdf
catch { file copy -force ${DESIGN_NAME}_postroute.sdf outputs/ }
rcOut -spef ${DESIGN_NAME}_postroute.spef
catch { file copy -force ${DESIGN_NAME}_postroute.spef outputs/ }
defOut -floorplan -netlist -routing ${DESIGN_NAME}_postroute.def
catch { file copy -force ${DESIGN_NAME}_postroute.def outputs/ }
catch { streamOut ${DESIGN_NAME}.gds -units 2000 -mode ALL }
saveDesign ${DESIGN_NAME}_final.enc
catch { file copy -force ${DESIGN_NAME}_final.enc db/ }

puts "========================================================"
puts " Physical Design Flow Completed Successfully! "
puts "========================================================"
