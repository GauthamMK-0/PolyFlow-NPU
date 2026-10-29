# Version:1.0 MMMC View Definition File
# Do Not Remove Above Line
# ==============================================================================
# Cadence Innovus Multi-Mode Multi-Corner (MMMC) Configuration File
# Aligned with mt_npu/models/pipelined/heterogeneous_fission/netlist/HDFF.view
# ------------------------------------------------------------------------------
# Target Library: 90nm Standard Cell Library (gsclib090_translated.lef)
# Setup Corner (MAX / SET_MAX / SETUP): slow.lib
# Hold Corner  (MIN / HOD_MIN / HOD):   fast.lib
# Capacitance  (CAP):                   gpdk090.lef.extended.CapTbl
# ==============================================================================

if {![info exists FOUNDRY_PATH]} {
    set FOUNDRY_PATH [expr {[info exists env(FOUNDRY_PATH)] ? $env(FOUNDRY_PATH) : "/home/cadence/install/FOUNDRY/digital/90nm/dig"}]
}

if {![info exists SLOW_LIB] || $SLOW_LIB eq ""} {
    set SLOW_LIB "${FOUNDRY_PATH}/lib/slow.lib"
}

if {![info exists FAST_LIB] || $FAST_LIB eq ""} {
    set FAST_LIB "${FOUNDRY_PATH}/lib/fast.lib"
}

if {![info exists CAP_TABLE] || $CAP_TABLE eq ""} {
    set CAP_TABLE "${FOUNDRY_PATH}/captable/gpdk090.lef.extended.CapTbl"
}

if {![info exists SDC_FILE] || $SDC_FILE eq ""} {
    if {[info exists DESIGN_NAME] && [file exists "netlist/${DESIGN_NAME}_netlist.sdc"]} {
        set SDC_FILE "netlist/${DESIGN_NAME}_netlist.sdc"
    } elseif {[info exists DESIGN_NAME] && [file exists "${DESIGN_NAME}_netlist.sdc"]} {
        set SDC_FILE "${DESIGN_NAME}_netlist.sdc"
    } elseif {[info exists DESIGN_NAME] && [file exists "${DESIGN_NAME}.sdc"]} {
        set SDC_FILE "${DESIGN_NAME}.sdc"
    } else {
        set SDC_FILE [lindex [glob -nocomplain netlist/*_netlist.sdc *_netlist.sdc *.sdc] 0]
    }
}

# 1. RC Corner Definition (CAP)
create_rc_corner -name CAP \
    -cap_table $CAP_TABLE \
    -preRoute_res {1.0} \
    -preRoute_cap {1.0} \
    -preRoute_clkres {0.0} \
    -preRoute_clkcap {0.0} \
    -postRoute_res {1.0} \
    -postRoute_cap {1.0} \
    -postRoute_xcap {1.0} \
    -postRoute_clkres {0.0} \
    -postRoute_clkcap {0.0}

# 2. Timing Library Sets (MAX & MIN)
create_library_set -name MAX -timing [list $SLOW_LIB]
create_library_set -name MIN -timing [list $FAST_LIB]

# 3. Constraint Mode (SDC)
create_constraint_mode -name SDC -sdc_files [list $SDC_FILE]

# 4. Delay Corners (SET_MAX & HOD_MIN)
create_delay_corner -name SET_MAX -library_set {MAX} -rc_corner {CAP}
create_delay_corner -name HOD_MIN -library_set {MIN} -rc_corner {CAP}

# 5. Analysis Views (SETUP & HOD)
create_analysis_view -name SETUP -constraint_mode {SDC} -delay_corner {SET_MAX}
create_analysis_view -name HOD   -constraint_mode {SDC} -delay_corner {HOD_MIN}

# 6. Set Active Analysis Views
set_analysis_view -setup {SETUP} -hold {HOD}
