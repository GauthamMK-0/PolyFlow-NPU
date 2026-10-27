# ============================================================================
# SELF-ADAPTING INNOVUS SCRIPT FOR gsclib090_translated.lef
# Automatically detects Site Name, Metal Layers, Clocks, and Filler Cells
# ============================================================================

# ---> ONLY EDIT THESE 4 PATHS/NAMES <---
set DESIGN_NAME  "hdf_top"                            ;# Your top Verilog module name
set NETLIST_FILE "netlist/hdf_top_netlist.v"          ;# Your Genus synthesized netlist
set LEF_FILES    "gsclib090_translated.lef"           ;# If you have tech.lef, put it first: "tech.lef gsclib090_translated.lef"
set MMMC_FILE    "viewDefinition_hdf_top.tcl"         ;# Your MMMC file

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
verify_drc -report ${DESIGN_NAME}_drc.rpt
verifyConnectivity -type all -report ${DESIGN_NAME}_connectivity.rpt

# Reports
summaryReport -noHtml -outfile ${DESIGN_NAME}_summary.rpt
report_power -outfile ${DESIGN_NAME}_power.rpt
if {[sizeof_collection $CLOCK_LIST] > 0} {
    timeDesign -postRoute -outDir timingReports
    timeDesign -postRoute -hold -outDir timingReports
}

# Outputs
saveNetlist ${DESIGN_NAME}_postroute.v
write_sdf ${DESIGN_NAME}_postroute.sdf
rcOut -spef ${DESIGN_NAME}_postroute.spef
defOut -floorplan -netlist -routing ${DESIGN_NAME}_postroute.def
catch { streamOut ${DESIGN_NAME}.gds -units 2000 -mode ALL }
saveDesign ${DESIGN_NAME}_final.enc

puts "========================================================"
puts " Physical Design Flow Completed Successfully! "
puts "========================================================"
