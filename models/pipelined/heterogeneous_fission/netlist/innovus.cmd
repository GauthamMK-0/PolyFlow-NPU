#######################################################
#                                                     
#  Innovus Command Logging File                     
#  Created on Tue Oct 27 11:39:16 2026                
#                                                     
#######################################################

#@(#)CDS: Innovus v21.15-s110_1 (64bit) 09/23/2022 13:08 (Linux 3.10.0-693.el7.x86_64)
#@(#)CDS: NanoRoute 21.15-s110_1 NR220912-2004/21_15-UB (database version 18.20.592) {superthreading v2.17}
#@(#)CDS: AAE 21.15-s039 (64bit) 09/23/2022 (Linux 3.10.0-693.el7.x86_64)
#@(#)CDS: CTE 21.15-s038_1 () Sep 20 2022 11:42:13 ( )
#@(#)CDS: SYNTECH 21.15-s012_1 () Sep  5 2022 10:25:51 ( )
#@(#)CDS: CPE v21.15-s076
#@(#)CDS: IQuantus/TQuantus 21.1.1-s867 (64bit) Sun Jun 26 22:12:54 PDT 2022 (Linux 3.10.0-693.el7.x86_64)

set_global _enable_mmmc_by_default_flow      $CTE::mmmc_default
suppressMessage ENCEXT-2799
getVersion
getVersion
getVersion
win
save_global HDFF.globals
set init_gnd_net VSS
set init_lef_file ../../../../../../../../cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_translated.lef
set init_verilog hdf_top_netlist.v
set init_mmmc_file HDFF.view
set init_pwr_net VDD
init_design
checkDesign -all
getIoFlowFlag
uiSetTool ruler
uiSetTool select
getIoFlowFlag
setIoFlowFlag 0
floorPlan -coreMarginsBy die -site gsclib090site -r 1 0.7 20 20 20 20
uiSetTool select
getIoFlowFlag
fit
set sprCreateIeRingOffset 1.0
set sprCreateIeRingThreshold 1.0
set sprCreateIeRingJogDistance 1.0
set sprCreateIeRingLayers {}
set sprCreateIeRingOffset 1.0
set sprCreateIeRingThreshold 1.0
set sprCreateIeRingJogDistance 1.0
set sprCreateIeRingLayers {}
set sprCreateIeStripeWidth 10.0
set sprCreateIeStripeThreshold 1.0
set sprCreateIeStripeWidth 10.0
set sprCreateIeStripeThreshold 1.0
set sprCreateIeRingOffset 1.0
set sprCreateIeRingThreshold 1.0
set sprCreateIeRingJogDistance 1.0
set sprCreateIeRingLayers {}
set sprCreateIeStripeWidth 10.0
set sprCreateIeStripeThreshold 1.0
setAddRingMode -ring_target default -extend_over_row 0 -ignore_rows 0 -avoid_short 0 -skip_crossing_trunks none -stacked_via_top_layer Metal9 -stacked_via_bottom_layer Metal1 -via_using_exact_crossover_size 1 -orthogonal_only true -skip_via_on_pin {  standardcell } -skip_via_on_wire_shape {  noshape }
addRing -nets {VDD VSS} -type core_rings -follow core -layer {top Metal9 bottom Metal9 left Metal8 right Metal8} -width {top 4 bottom 4 left 4 right 4} -spacing {top 4 bottom 4 left 4 right 4} -offset {top 4 bottom 4 left 4 right 4} -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None
set sprCreateIeRingOffset 1.0
set sprCreateIeRingThreshold 1.0
set sprCreateIeRingJogDistance 1.0
set sprCreateIeRingLayers {}
set sprCreateIeRingOffset 1.0
set sprCreateIeRingThreshold 1.0
set sprCreateIeRingJogDistance 1.0
set sprCreateIeRingLayers {}
set sprCreateIeStripeWidth 10.0
set sprCreateIeStripeThreshold 1.0
set sprCreateIeStripeWidth 10.0
set sprCreateIeStripeThreshold 1.0
set sprCreateIeRingOffset 1.0
set sprCreateIeRingThreshold 1.0
set sprCreateIeRingJogDistance 1.0
set sprCreateIeRingLayers {}
set sprCreateIeStripeWidth 10.0
set sprCreateIeStripeThreshold 1.0
setAddStripeMode -ignore_block_check false -break_at none -route_over_rows_only false -rows_without_stripes_only false -extend_to_closest_target none -stop_at_last_wire_for_area false -partial_set_thru_domain false -ignore_nondefault_domains false -trim_antenna_back_to_shape none -spacing_type edge_to_edge -spacing_from_block 0 -stripe_min_length stripe_width -stacked_via_top_layer Metal9 -stacked_via_bottom_layer Metal1 -via_using_exact_crossover_size false -split_vias false -orthogonal_only true -allow_jog { padcore_ring  block_ring } -skip_via_on_pin {  standardcell } -skip_via_on_wire_shape {  noshape   }
addStripe -nets {VDD VSS} -layer Metal9 -direction horizontal -width 4 -spacing 4 -number_of_sets 6 -start_from bottom -switch_layer_over_obs false -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit Metal9 -padcore_ring_bottom_layer_limit Metal1 -block_ring_top_layer_limit Metal9 -block_ring_bottom_layer_limit Metal1 -use_wire_group 0 -snap_wire_center_to_grid None
setAddStripeMode -ignore_block_check false -break_at none -route_over_rows_only false -rows_without_stripes_only false -extend_to_closest_target none -stop_at_last_wire_for_area false -partial_set_thru_domain false -ignore_nondefault_domains false -trim_antenna_back_to_shape none -spacing_type edge_to_edge -spacing_from_block 0 -stripe_min_length stripe_width -stacked_via_top_layer Metal9 -stacked_via_bottom_layer Metal1 -via_using_exact_crossover_size false -split_vias false -orthogonal_only true -allow_jog { padcore_ring  block_ring } -skip_via_on_pin {  standardcell } -skip_via_on_wire_shape {  noshape   }
addStripe -nets {VDD VSS} -layer Metal8 -direction vertical -width 4 -spacing 4 -number_of_sets 6 -start_from left -switch_layer_over_obs false -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit Metal9 -padcore_ring_bottom_layer_limit Metal1 -block_ring_top_layer_limit Metal9 -block_ring_bottom_layer_limit Metal1 -use_wire_group 0 -snap_wire_center_to_grid None
zoomBox 77.71500 393.49500 118.54950 340.41050
fit
setSrouteMode -viaConnectToShape { noshape }
sroute -connect { blockPin padPin padRing corePin floatingStripe } -layerChangeRange { Metal1(1) Metal9(9) } -blockPinTarget { nearestTarget } -padPinPortConnect { allPort oneGeom } -padPinTarget { nearestTarget } -corePinTarget { firstAfterRowEnd } -floatingStripeTarget { blockring padring ring stripe ringpin blockpin followpin } -allowJogging 1 -crossoverViaLayerRange { Metal1(1) Metal9(9) } -nets { VDD VSS } -allowLayerChange 1 -blockPin useLef -targetViaLayerRange { Metal1(1) Metal9(9) }
saveDesign hdff_top_power.enc
timeDesign -prePlace -setup
optDesign -preplace -setup
optDesign -prePlace -setup
optDesign -prePlace
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
setPlaceMode -congEffort auto -timingDriven 1 -clkGateAware 1 -powerDriven 0 -ignoreScan 1 -reorderScan 1 -ignoreSpare 0 -placeIOPins 1 -moduleAwareSpare 0 -preserveRouting 1 -rmAffectedRouting 0 -checkRoute 0 -swapEEQ 0
setPlaceMode -fp false
place_design
optDesign -preCTS
setDrawView fplan
setDrawView place
setLayerPreference node_net -isVisible 0
zoomBox 129.98300 337.14350 201.85150 257.92500
fit
setLayerPreference node_net -isVisible 1
add_ndr -width {Metal1 0.14 Metal2 0.16 Metal3 0.14 Metal4 0.14 Metal5 0.14 Metal6 0.14 Metal7 0.14 Metal8 0.46 Metal9 0.46 } -spacing {Metal1 0.14 Metal2 0.16 Metal3 0.14 Metal4 0.14 Metal5 0.14 Metal6 0.14 Metal7 0.14 Metal8 0.46 Metal9 0.46 } -name 2w2s
create_route_type -name clkroute -non_default_rule 2w2s -bottom_preferred_layer Metal5 -top_preferred_layer Metal6
set_ccopt_property route_type clkroute -net_type trunk
set_ccopt_property route_type clkroute -net_type leaf
set_ccopt_property buffer_cells {CLKBUFX6 CLKBUFX8 CLKBUFX12}
set_ccopt_property inverter_cells {CLKINVX6 CLKINVX8 CLKINVX12}
set_ccopt_property clock_gating_cells TLATNTSCA*
set_ccopt_property target_max_trans 0.5
create_ccopt_clock_tree_spec -file ccopt.spec
get_ccopt_clock_trees
ccopt_check_and_flatten_ilms_no_restore
set_ccopt_property cts_is_sdc_clock_root -pin clk true
create_ccopt_clock_tree -name clk -source clk -no_skew_group
set_ccopt_property target_max_trans_sdc -delay_corner SET_MAX -early -clock_tree clk 0.050
set_ccopt_property target_max_trans_sdc -delay_corner SET_MAX -late -clock_tree clk 0.050
set_ccopt_property clock_period -pin clk 5
set_ccopt_property timing_connectivity_info {}
create_ccopt_skew_group -name clk/SDC -sources clk -auto_sinks
set_ccopt_property include_source_latency -skew_group clk/SDC true
set_ccopt_property extracted_from_clock_name -skew_group clk/SDC clk
set_ccopt_property extracted_from_constraint_mode_name -skew_group clk/SDC SDC
set_ccopt_property extracted_from_delay_corners -skew_group clk/SDC {SET_MAX HOD_MIN}
check_ccopt_clock_tree_convergence
get_ccopt_property auto_design_state_for_ilms
ccopt_design -cts
saveDesign DBS/cts.enc
report_ccopt_clock_trees -file clk_trees.rpt
report_ccopt_skew_groups -file skew_groups.rpt
timeDesign -postCTS -setup -hold
optDesign -postCTS -setup -hold
optDesign -postCTS -hold
setLayerPreference clock -isVisible 0
setLayerPreference node_net -isVisible 1
setLayerPreference clock -isVisible 0
setLayerPreference node_net -isVisible 1
setLayerPreference node_net -isVisible 0
setLayerPreference clock -isVisible 1
zoomBox 7.48000 377.16150 80.16500 319.17650
fit
zoomBox 189.60150 410.64550 214.10200 356.74400
zoomBox 196.93750 398.48750 205.24600 390.07800
zoomBox 200.29350 395.89500 200.94150 393.69800
zoomBox 200.32200 395.36250 200.65650 394.90800
zoomBox 200.60750 395.00700 200.63750 394.98050
zoomBox 200.62150 394.99950 200.62850 394.98850
fit
zoomBox 192.86800 406.56200 210.83550 377.97800
zoomBox 198.92300 397.37450 201.93200 392.75350
zoomBox 200.36250 395.44600 200.74450 394.69900
zoomBox 200.36350 395.34050 200.67950 394.85350
zoomOut
zoomOut
zoomOut
zoomOut
zoomOut
zoomOut
zoomOut
fit
setLayerPreference node_net -isVisible 1
set dbgLefDefOutVersion 5.8
global dbgLefDefOutVersion
set dbgLefDefOutVersion 5.8
defOut -floorplan -netlist -routing hdf_top_cts.def
set dbgLefDefOutVersion 5.8
set dbgLefDefOutVersion 5.8
saveDesign hdff_top_cts.enc
getCTSMode -engine -quiet
getCTSMode -engine -quiet
getCTSMode -engine -quiet
ctd_win -side none -id ctd_window
getAnalysisMode -checkType -quiet
get_time_unit
report_timing -machine_readable -max_paths 10000 -max_slack 0.75 -path_exceptions all -late > top.mtarpt
load_timing_debug_report -name default_report top.mtarpt -max_path_num 10000 -updateCategory 0
getAnalysisMode -checkType -quiet
get_time_unit
report_timing -machine_readable -max_paths 10000 -max_slack 0.75 -path_exceptions all -early > top.mtarpt
load_timing_debug_report -name default_report top.mtarpt -max_path_num 10000 -updateCategory 0
setNanoRouteMode -quiet -routeTopRoutingLayer 9
setNanoRouteMode -quiet -routeBottomRoutingLayer 1
setNanoRouteMode -quiet -drouteEndIteration 1
setNanoRouteMode -quiet -routeWithTimingDriven false
setNanoRouteMode -quiet -routeWithSiDriven false
routeDesign -globalDetail
setDrawView fplan
setDrawView ameba
setDrawView place
setLayerPreference node_layer -isVisible 0
getFillerMode -quiet
addFiller -cell FILL1 FILL2 FILL4 FILL8 FILL16 -prefix FILLER
setLayerPreference node_layer -isVisible 1
timeDesign -postRoute -setup -hold
setAnalysisMode -analysisType onChipVariation -cppr both
timeDesign -postRoute -setup -hold
optDesign -postRoute -setup -hold
getAnalysisMode -checkType -quiet
get_time_unit
report_timing -machine_readable -max_paths 10000 -max_slack 0.75 -path_exceptions all -late > top.mtarpt
load_timing_debug_report -name default_report top.mtarpt -max_path_num 10000 -updateCategory 0
saveDesign hdff_top_routed.enc
set dbgLefDefOutVersion 5.8
global dbgLefDefOutVersion
set dbgLefDefOutVersion 5.8
defOut -floorplan -netlist -routing hdf_top.def
set dbgLefDefOutVersion 5.8
set dbgLefDefOutVersion 5.8
set dbgLefDefOutVersion 5.8
global dbgLefDefOutVersion
set dbgLefDefOutVersion 5.8
defOut -floorplan -netlist -routing hdf_top_routed.def
set dbgLefDefOutVersion 5.8
set dbgLefDefOutVersion 5.8
report_power
