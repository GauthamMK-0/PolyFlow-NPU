# ==============================================================================
# Cadence Innovus Physical Design Script: Up to Standard Cell Placement
# Target: 90nm Standard Cell Library
# Design: sfa_top (Model 2: Homogeneous Spatial Fission)
# Flow: Design Init -> Floorplan -> Power Rings/SRoute -> Placement & Pre-CTS Opt
# ==============================================================================

# --- 1. Top Module & Directories ---
set TOP_MODULE "sfa_top"

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
puts " Target: 90nm Technology | CPUs: $MULTI_CPU"
puts "=================================================================="

# --- 3. Technology & Library Paths ---
set FOUNDRY_PATH [expr {[info exists env(FOUNDRY_PATH)] ? $env(FOUNDRY_PATH) : "/home/cadence/install/FOUNDRY/digital/90nm/dig"}]
set TECH_LEF     [expr {[info exists env(TECH_LEF)]     ? $env(TECH_LEF)     : "${FOUNDRY_PATH}/lef/technology.lef"}]
set CELL_LEF     [expr {[info exists env(CELL_LEF)]     ? $env(CELL_LEF)     : "${FOUNDRY_PATH}/lef/slow.lef"}]
set TARGET_LIB   [expr {[info exists env(TARGET_LIB)]   ? $env(TARGET_LIB)   : "${FOUNDRY_PATH}/lib/slow.lib"}]

# Netlist & SDC paths
set NETLIST_FILE "netlist/${TOP_MODULE}_netlist.v"
if {![file exists $NETLIST_FILE]} {
    if {[file exists "${TOP_MODULE}_netlist.v"]} {
        set NETLIST_FILE "${TOP_MODULE}_netlist.v"
    } else {
        puts "WARNING: Synthesized netlist $NETLIST_FILE not found! Ensure Genus synthesis has completed."
    }
}

set SDC_FILE "netlist/${TOP_MODULE}_netlist.sdc"
if {![file exists $SDC_FILE]} {
    set SDC_FILE "${TOP_MODULE}.sdc"
}

# --- 4. Design Initialization & Analysis View Setup ---
puts "--- Phase 1: Initializing Design and Constraints ---"

create_rc_corner -name default_rc_corner -T 125
create_library_set -name slow_lib_set -timing [list $TARGET_LIB]
create_constraint_mode -name default_constraint_mode -sdc_files [list $SDC_FILE]
create_delay_corner -name slow_delay_corner -library_set slow_lib_set -rc_corner default_rc_corner
create_analysis_view -name default_analysis_view -constraint_mode default_constraint_mode -delay_corner slow_delay_corner

set init_gnd_net "VSS"
set init_pwr_net "VDD"
set init_verilog $NETLIST_FILE
set init_top_cell $TOP_MODULE
set init_lef_file [list $TECH_LEF $CELL_LEF]
set init_mmmc_file ""

init_design -setup {default_analysis_view} -hold {default_analysis_view}

clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {}
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {}
globalNetConnect VDD -type tiehi -inst * -module {}
globalNetConnect VSS -type tielo -inst * -module {}

# --- 5. Floorplanning ---
puts "--- Phase 2: Floorplanning (Core Util: 70%, Margins: 10 um) ---"
floorPlan -site CoreSite -r 1.0 0.70 10.0 10.0 10.0 10.0

# --- 6. Power Planning: Rings & Standard Cell Rails (SRoute) ---
puts "--- Phase 3: Power Planning (Core Rings & SRoute) ---"

addRing -nets {VDD VSS} -type core_rings -follow core \
    -layer {top Metal6 bottom Metal6 left Metal5 right Metal5} \
    -width 2.0 -spacing 1.0 -offset 2.0

sroute -connect { corePin } \
    -layerChangeRange { Metal1 Metal6 } \
    -blockPinTarget { nearestTarget } \
    -corePinTarget { firstAfterRowEnd } \
    -nets { VDD VSS }

# --- 7. Standard Cell Placement & Pre-CTS Optimization ---
puts "--- Phase 4: Standard Cell Placement & Pre-CTS Optimization ---"

setPlaceMode -prerouteResourceBudget true \
             -timingDriven true \
             -congEffort high \
             -modulePadding 1.0

catch {
    place_opt_design -prefix place
} catch_err

if {[info exists catch_err] && $catch_err ne ""} {
    puts "place_opt_design reported: $catch_err. Attempting place_design fallback..."
    place_design -concurrent
    optDesign -preCTS
}

# --- 8. Post-Placement Diagnostics & Reports ---
puts "--- Phase 5: Generating Post-Placement Reports ---"

checkPlace $REPORT_DIR/check_place.rpt
report_density > $REPORT_DIR/density_place.rpt
timeDesign -preCTS -prefix place -outDir $REPORT_DIR
reportCongestion -hotSpot > $REPORT_DIR/congestion_place.rpt

# --- 9. Save Placement Checkpoint Database ---
saveDesign $DB_DIR/${TOP_MODULE}_placed.enc

puts "=================================================================="
puts " Innovus Placement Stage Complete!"
puts " Placed Database Saved: $DB_DIR/${TOP_MODULE}_placed.enc"
puts " Diagnostic Reports:    $REPORT_DIR/"
puts "=================================================================="
