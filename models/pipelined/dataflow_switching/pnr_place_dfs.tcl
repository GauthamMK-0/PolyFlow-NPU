# ============================================================================
# CADENCE INNOVUS PHYSICAL DESIGN SCRIPT FOR gsclib090_translated.lef
# Aligned with mt_npu/models/pipelined/heterogeneous_fission/netlist/innovus.cmd
# Target: 90nm Standard Cell Library (gsclib090_translated.lef)
# Design: dfs_top (Model 1: Single-Tenant Dataflow Switching (Pipelined))
# MMMC: slow.lib (MAX/SETUP), fast.lib (MIN/HOD), gpdk090.lef.extended.CapTbl (CAP)
# Flow Scope: Full Physical Design Flow (Floorplan, PDN, Place, CTS, Route)
# ============================================================================

# ---> ONLY EDIT THESE 4 PATHS/NAMES <---
set DESIGN_NAME  "dfs_top"                                     ;# Top Verilog module name
set NETLIST_FILE "netlist/dfs_top_netlist.v"                   ;# Genus synthesized gate-level netlist
set LEF_FILES    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_translated.lef"
set MMMC_FILE    "viewDefinition_dfs_top.tcl"                         ;# MMMC configuration file

# Execution Control: Set to 0 for complete Post-Route flow (per innovus.cmd); set to 1 to stop at CTS
set STOP_AT_CTS  0

# ----------------------------------------------------------------------------
# 0. Path & Environment Resolution
# ----------------------------------------------------------------------------
set MULTI_CPU [expr {[info exists env(PNR_CPUS)] ? $env(PNR_CPUS) : 4}]
catch { setMultiCpuUsage -localCpu $MULTI_CPU -keepLicense true }

set FOUNDRY_PATH [expr {[info exists env(FOUNDRY_PATH)] ? $env(FOUNDRY_PATH) : "/home/cadence/install/FOUNDRY/digital/90nm/dig"}]

# Output directories
file mkdir db
file mkdir DBS
file mkdir outputs
file mkdir reports/cts

if {![file exists $NETLIST_FILE] && [file exists "${DESIGN_NAME}_netlist.v"]} {
    set NETLIST_FILE "${DESIGN_NAME}_netlist.v"
}

if {![file exists $LEF_FILES] && [file exists "${FOUNDRY_PATH}/lef/gsclib090_translated.lef"]} {
    set LEF_FILES "${FOUNDRY_PATH}/lef/gsclib090_translated.lef"
}

set SLOW_LIB "${FOUNDRY_PATH}/lib/slow.lib"
set FAST_LIB "${FOUNDRY_PATH}/lib/fast.lib"
set CAP_TABLE "${FOUNDRY_PATH}/captable/gpdk090.lef.extended.CapTbl"

if {[file exists "netlist/${DESIGN_NAME}_netlist.sdc"]} {
    set SDC_FILE "netlist/${DESIGN_NAME}_netlist.sdc"
} elseif {[file exists "${DESIGN_NAME}_netlist.sdc"]} {
    set SDC_FILE "${DESIGN_NAME}_netlist.sdc"
} else {
    set SDC_FILE "${DESIGN_NAME}.sdc"
}

# Auto-generate MMMC file if missing (exact HDFF.view structure)
if {![file exists $MMMC_FILE]} {
    set fp_mmmc [open $MMMC_FILE w]
    puts $fp_mmmc "# Version:1.0 MMMC View Definition File"
    puts $fp_mmmc "# Do Not Remove Above Line"
    puts $fp_mmmc "create_rc_corner -name CAP -cap_table {$CAP_TABLE} -preRoute_res {1.0} -preRoute_cap {1.0} -preRoute_clkres {0.0} -preRoute_clkcap {0.0} -postRoute_res {1.0} -postRoute_cap {1.0} -postRoute_xcap {1.0} -postRoute_clkres {0.0} -postRoute_clkcap {0.0}"
    puts $fp_mmmc "create_library_set -name MAX -timing {$SLOW_LIB}"
    puts $fp_mmmc "create_library_set -name MIN -timing {$FAST_LIB}"
    puts $fp_mmmc "create_constraint_mode -name SDC -sdc_files {$SDC_FILE}"
    puts $fp_mmmc "create_delay_corner -name SET_MAX -library_set {MAX} -rc_corner {CAP}"
    puts $fp_mmmc "create_delay_corner -name HOD_MIN -library_set {MIN} -rc_corner {CAP}"
    puts $fp_mmmc "create_analysis_view -name SETUP -constraint_mode {SDC} -delay_corner {SET_MAX}"
    puts $fp_mmmc "create_analysis_view -name HOD -constraint_mode {SDC} -delay_corner {HOD_MIN}"
    puts $fp_mmmc "set_analysis_view -setup {SETUP} -hold {HOD}"
    close $fp_mmmc
}

puts "=================================================================="
puts " Innovus Physical Design Parameters:"
puts "   DESIGN_NAME:  $DESIGN_NAME"
puts "   NETLIST_FILE: $NETLIST_FILE"
puts "   LEF_FILES:    $LEF_FILES"
puts "   MMMC_FILE:    $MMMC_FILE"
puts "   SETUP_LIB:    $SLOW_LIB"
puts "   HOLD_LIB:     $FAST_LIB"
puts "   CAP_TABLE:    $CAP_TABLE"
puts "=================================================================="

# ----------------------------------------------------------------------------
# 1. Design Import & Initialization (Matching innovus.cmd & HDFF.globals)
# ----------------------------------------------------------------------------
set_global _enable_mmmc_by_default_flow $CTE::mmmc_default
suppressMessage ENCEXT-2799

set init_gnd_net VSS
set init_lef_file $LEF_FILES
set init_verilog $NETLIST_FILE
set init_mmmc_file $MMMC_FILE
set init_pwr_net VDD
set init_top_cell $DESIGN_NAME
set init_design_settop 1
set init_design_uniquify 1

init_design
checkDesign -all

saveDesign db/${DESIGN_NAME}_01_init.enc

# ----------------------------------------------------------------------------
# 2. Floorplanning (Matching innovus.cmd: gsclib090site, -r 1 0.7 20 20 20 20)
# ----------------------------------------------------------------------------
getIoFlowFlag
setIoFlowFlag 0
floorPlan -coreMarginsBy die -site gsclib090site -r 1 0.7 20 20 20 20
fit

# Global Power/Ground Net Connections
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst *
globalNetConnect VSS -type pgpin -pin VSS -inst *
globalNetConnect VDD -type tiehi -inst *
globalNetConnect VSS -type tielo -inst *

# ----------------------------------------------------------------------------
# 3. Power Network Design (PDN: Metal9 Horizontal / Metal8 Vertical, width 4, spacing 4)
# ----------------------------------------------------------------------------
set sprCreateIeRingOffset 1.0
set sprCreateIeRingThreshold 1.0
set sprCreateIeRingJogDistance 1.0
set sprCreateIeRingLayers {}
set sprCreateIeStripeWidth 10.0
set sprCreateIeStripeThreshold 1.0

setAddRingMode -ring_target default -extend_over_row 0 -ignore_rows 0 -avoid_short 0 \
    -skip_crossing_trunks none -stacked_via_top_layer Metal9 -stacked_via_bottom_layer Metal1 \
    -via_using_exact_crossover_size 1 -orthogonal_only true \
    -skip_via_on_pin { standardcell } -skip_via_on_wire_shape { noshape }

addRing -nets {VDD VSS} -type core_rings -follow core \
    -layer {top Metal9 bottom Metal9 left Metal8 right Metal8} \
    -width {top 4 bottom 4 left 4 right 4} \
    -spacing {top 4 bottom 4 left 4 right 4} \
    -offset {top 4 bottom 4 left 4 right 4} \
    -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None

setAddStripeMode -ignore_block_check false -break_at none -route_over_rows_only false \
    -rows_without_stripes_only false -extend_to_closest_target none \
    -stop_at_last_wire_for_area false -partial_set_thru_domain false \
    -ignore_nondefault_domains false -trim_antenna_back_to_shape none \
    -spacing_type edge_to_edge -spacing_from_block 0 -stripe_min_length stripe_width \
    -stacked_via_top_layer Metal9 -stacked_via_bottom_layer Metal1 \
    -via_using_exact_crossover_size false -split_vias false -orthogonal_only true \
    -allow_jog { padcore_ring block_ring } \
    -skip_via_on_pin { standardcell } -skip_via_on_wire_shape { noshape }

# Horizontal Power Stripes on Metal9 (6 sets)
addStripe -nets {VDD VSS} -layer Metal9 -direction horizontal \
    -width 4 -spacing 4 -number_of_sets 6 -start_from bottom \
    -switch_layer_over_obs false -max_same_layer_jog_length 2 \
    -padcore_ring_top_layer_limit Metal9 -padcore_ring_bottom_layer_limit Metal1 \
    -block_ring_top_layer_limit Metal9 -block_ring_bottom_layer_limit Metal1 \
    -use_wire_group 0 -snap_wire_center_to_grid None

# Vertical Power Stripes on Metal8 (6 sets)
addStripe -nets {VDD VSS} -layer Metal8 -direction vertical \
    -width 4 -spacing 4 -number_of_sets 6 -start_from left \
    -switch_layer_over_obs false -max_same_layer_jog_length 2 \
    -padcore_ring_top_layer_limit Metal9 -padcore_ring_bottom_layer_limit Metal1 \
    -block_ring_top_layer_limit Metal9 -block_ring_bottom_layer_limit Metal1 \
    -use_wire_group 0 -snap_wire_center_to_grid None

# Special Route (sroute) across Metal1(1) to Metal9(9)
setSrouteMode -viaConnectToShape { noshape }
sroute -connect { blockPin padPin padRing corePin floatingStripe } \
    -layerChangeRange { Metal1(1) Metal9(9) } \
    -blockPinTarget { nearestTarget } \
    -padPinPortConnect { allPort oneGeom } \
    -padPinTarget { nearestTarget } \
    -corePinTarget { firstAfterRowEnd } \
    -floatingStripeTarget { blockring padring ring stripe ringpin blockpin followpin } \
    -allowJogging 1 \
    -crossoverViaLayerRange { Metal1(1) Metal9(9) } \
    -nets { VDD VSS } \
    -allowLayerChange 1 \
    -blockPin useLef \
    -targetViaLayerRange { Metal1(1) Metal9(9) }

saveDesign ${DESIGN_NAME}_power.enc
saveDesign db/${DESIGN_NAME}_02_power.enc

# ----------------------------------------------------------------------------
# 4. Pre-Place Timing, Standard Cell Placement & Pre-CTS Optimization
# ----------------------------------------------------------------------------
timeDesign -prePlace -setup

setPlaceMode -fp false
place_design
timeDesign -preCTS

setRouteMode -earlyGlobalHonorMsvRouteConstraint false -earlyGlobalRoutePartitionPinGuide true
setEndCapMode -reset
setEndCapMode -boundary_tap false
setNanoRouteMode -quiet -droutePostRouteSpreadWire 1
setNanoRouteMode -quiet -droutePostRouteWidenWireRule LEFDefaultRouteSpec_gpdk090
setNanoRouteMode -quiet -timingEngine {}
setUsefulSkewMode -noBoundary false -maxAllowedDelay 1

setPlaceMode -reset
setPlaceMode -congEffort auto -timingDriven 1 -clkGateAware 1 -powerDriven 0 \
    -ignoreScan 1 -reorderScan 1 -ignoreSpare 0 -placeIOPins 1 \
    -moduleAwareSpare 0 -preserveRouting 1 -rmAffectedRouting 0 \
    -checkRoute 0 -swapEEQ 0
setPlaceMode -fp false
place_design
optDesign -preCTS

saveDesign db/${DESIGN_NAME}_03_placed.enc

# ----------------------------------------------------------------------------
# 5. Clock Tree Synthesis (CCOpt Engine - Matching cts.tcl & ccopt.spec)
# ----------------------------------------------------------------------------
add_ndr -width {Metal1 0.14 Metal2 0.16 Metal3 0.14 Metal4 0.14 Metal5 0.14 Metal6 0.14 Metal7 0.14 Metal8 0.46 Metal9 0.46 } \
        -spacing {Metal1 0.14 Metal2 0.16 Metal3 0.14 Metal4 0.14 Metal5 0.14 Metal6 0.14 Metal7 0.14 Metal8 0.46 Metal9 0.46 } \
        -name 2w2s
create_route_type -name clkroute -non_default_rule 2w2s -bottom_preferred_layer Metal5 -top_preferred_layer Metal6
set_ccopt_property route_type clkroute -net_type trunk
set_ccopt_property route_type clkroute -net_type leaf
set_ccopt_property buffer_cells {CLKBUFX6 CLKBUFX8 CLKBUFX12}
set_ccopt_property inverter_cells {CLKINVX6 CLKINVX8 CLKINVX12}
set_ccopt_property clock_gating_cells TLATNTSCA*
set_ccopt_property target_max_trans 0.5

create_ccopt_clock_tree_spec -file ccopt.spec
source ccopt.spec
ccopt_design -cts

saveDesign DBS/cts.enc
saveDesign db/${DESIGN_NAME}_04_cts.enc

report_ccopt_clock_trees -file clk_trees.rpt
report_ccopt_skew_groups -file skew_groups.rpt
report_ccopt_clock_trees -file reports/cts/${DESIGN_NAME}_clock_trees.rpt
report_ccopt_skew_groups -file reports/cts/${DESIGN_NAME}_skew_groups.rpt

# ----------------------------------------------------------------------------
# 6. Post-CTS Timing Optimization (Setup & Hold)
# ----------------------------------------------------------------------------
timeDesign -postCTS -setup -hold
optDesign -postCTS -setup -hold
optDesign -postCTS -hold

set dbgLefDefOutVersion 5.8
global dbgLefDefOutVersion
set dbgLefDefOutVersion 5.8
defOut -floorplan -netlist -routing ${DESIGN_NAME}_cts.def
defOut -floorplan -netlist -routing outputs/${DESIGN_NAME}_cts.def
saveNetlist outputs/${DESIGN_NAME}_cts.v
write_sdf outputs/${DESIGN_NAME}_cts.sdf

saveDesign ${DESIGN_NAME}_cts.enc
saveDesign db/${DESIGN_NAME}_05_postcts.enc

if {$STOP_AT_CTS} {
    puts "INFO: STOP_AT_CTS is enabled (Flow completed at Post-CTS stage)."
    return
}

# ----------------------------------------------------------------------------
# 7. Detailed Routing (NanoRoute), Post-Route Optimization & Filler Insertion
# ----------------------------------------------------------------------------
setNanoRouteMode -quiet -routeTopRoutingLayer 9
setNanoRouteMode -quiet -routeBottomRoutingLayer 1
setNanoRouteMode -quiet -drouteEndIteration 1
setNanoRouteMode -quiet -routeWithTimingDriven false
setNanoRouteMode -quiet -routeWithSiDriven false
routeDesign -globalDetail

# Post-Route OCV & CPPR Timing Analysis and Optimization
setAnalysisMode -analysisType onChipVariation -cppr both
timeDesign -postRoute -setup -hold
optDesign -postRoute -setup -hold

# Add Standard Cell Fillers (FILL1, FILL2, FILL4, FILL8, FILL16)
addFiller -cell FILL1 FILL2 FILL4 FILL8 FILL16 -prefix FILLER

# ----------------------------------------------------------------------------
# 8. Final Signoff Deliverables & Reports
# ----------------------------------------------------------------------------
saveDesign ${DESIGN_NAME}_routed.enc
saveDesign db/${DESIGN_NAME}_06_postroute.enc

set dbgLefDefOutVersion 5.8
global dbgLefDefOutVersion
set dbgLefDefOutVersion 5.8
defOut -floorplan -netlist -routing ${DESIGN_NAME}.def
defOut -floorplan -netlist -routing ${DESIGN_NAME}_routed.def
defOut -floorplan -netlist -routing outputs/${DESIGN_NAME}_postroute.def

saveNetlist outputs/${DESIGN_NAME}_postroute.v
write_sdf outputs/${DESIGN_NAME}_postroute.sdf

report_power
report_power -outfile reports/${DESIGN_NAME}_postroute_power.rpt
summaryReport -noHtml -outfile reports/${DESIGN_NAME}_postroute_summary.rpt
verify_drc -report reports/${DESIGN_NAME}_postroute_drc.rpt
verifyConnectivity -type all -report reports/${DESIGN_NAME}_postroute_connectivity.rpt

puts "========================================================"
puts " Full Physical Design Flow Completed Successfully!      "
puts "========================================================"
