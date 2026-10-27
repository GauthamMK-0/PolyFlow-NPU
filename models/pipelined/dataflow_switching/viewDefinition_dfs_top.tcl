# ==============================================================================
# Cadence Innovus Multi-Mode Multi-Corner (MMMC) Configuration File
# ------------------------------------------------------------------------------
# Target Library: 90nm Bulk CMOS Standard Cell Library (gsclib090)
# Setup Corner (Max / Late):  slow.lib @ 125C, worst RC
# Hold Corner  (Min / Early): fast.lib @ -40C, best RC
# Capacitance Extraction:     CapTable (gsclib090.capTable / captable)
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. Intelligent Variable & Search Path Resolution
# ------------------------------------------------------------------------------
if {![info exists FOUNDRY_PATH]} {
    set FOUNDRY_PATH [expr {[info exists env(FOUNDRY_PATH)] ? $env(FOUNDRY_PATH) : "/home/cadence/install/FOUNDRY/digital/90nm/dig"}]
}

# Setup Timing Library (slow.lib)
if {![info exists SLOW_LIB] || $SLOW_LIB eq ""} {
    set SLOW_LIB [expr {[info exists env(SLOW_LIB)] ? $env(SLOW_LIB) : ""}]
    if {$SLOW_LIB eq ""} {
        set SLOW_CANDS [list \
            "${FOUNDRY_PATH}/lib/slow.lib" \
            "${FOUNDRY_PATH}/lib/gsclib090_slow.lib" \
            "slow.lib" \
            "gsclib090_slow.lib" \
            "../slow.lib" \
            "../../slow.lib" \
            "lib/slow.lib" \
            "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib" \
        ]
        foreach cand $SLOW_CANDS {
            if {[file exists $cand]} {
                set SLOW_LIB [file normalize $cand]
                break
            }
        }
        if {$SLOW_LIB eq ""} { set SLOW_LIB "${FOUNDRY_PATH}/lib/slow.lib" }
    }
}

# Hold Timing Library (fast.lib)
if {![info exists FAST_LIB] || $FAST_LIB eq ""} {
    set FAST_LIB [expr {[info exists env(FAST_LIB)] ? $env(FAST_LIB) : ""}]
    if {$FAST_LIB eq ""} {
        set FAST_CANDS [list \
            "${FOUNDRY_PATH}/lib/fast.lib" \
            "${FOUNDRY_PATH}/lib/gsclib090_fast.lib" \
            "fast.lib" \
            "gsclib090_fast.lib" \
            "../fast.lib" \
            "../../fast.lib" \
            "lib/fast.lib" \
            "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/fast.lib" \
        ]
        foreach cand $FAST_CANDS {
            if {[file exists $cand]} {
                set FAST_LIB [file normalize $cand]
                break
            }
        }
        if {$FAST_LIB eq ""} { set FAST_LIB "${FOUNDRY_PATH}/lib/fast.lib" }
    }
}

# Capacitance Table (captable)
if {![info exists CAP_TABLE] || $CAP_TABLE eq ""} {
    set CAP_TABLE [expr {[info exists env(CAP_TABLE)] ? $env(CAP_TABLE) : ""}]
    if {$CAP_TABLE eq ""} {
        set CAP_CANDS [list \
            "${FOUNDRY_PATH}/capTable/gsclib090.capTable" \
            "${FOUNDRY_PATH}/capTable/captable" \
            "${FOUNDRY_PATH}/captable/gsclib090.capTable" \
            "${FOUNDRY_PATH}/captable" \
            "${FOUNDRY_PATH}/tech/captable" \
            "gsclib090.capTable" \
            "captable" \
            "cln90.capTable" \
            "../gsclib090.capTable" \
            "../../gsclib090.capTable" \
            "/home/cadence/install/FOUNDRY/digital/90nm/dig/capTable/gsclib090.capTable" \
        ]
        foreach cand $CAP_CANDS {
            if {[file exists $cand]} {
                set CAP_TABLE [file normalize $cand]
                break
            }
        }
        if {$CAP_TABLE eq ""} { set CAP_TABLE "${FOUNDRY_PATH}/capTable/gsclib090.capTable" }
    }
}

# Ensure a valid CapTable file exists to avoid Innovus load error
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

# SDC Timing Constraints File
if {![info exists SDC_FILE] || $SDC_FILE eq ""} {
    set SDC_FILE [expr {[info exists env(SDC_FILE)] ? $env(SDC_FILE) : ""}]
    if {$SDC_FILE eq ""} {
        if {[info exists DESIGN_NAME]} {
            set SDC_CANDS [list \
                "netlist/${DESIGN_NAME}_netlist.sdc" \
                "${DESIGN_NAME}.sdc" \
                "../${DESIGN_NAME}.sdc" \
                "netlist/${DESIGN_NAME}.sdc" \
                "${DESIGN_NAME}_fallback.sdc" \
            ]
            foreach cand $SDC_CANDS {
                if {[file exists $cand]} {
                    set SDC_FILE [file normalize $cand]
                    break
                }
            }
        }
    }
}
if {$SDC_FILE eq "" || ![file exists $SDC_FILE]} {
    set SDC_FILE "fallback.sdc"
}

puts "=================================================================="
puts " Innovus MMMC Multi-Corner Configuration Initialized:"
puts "   Setup Timing Library (Max): $SLOW_LIB"
puts "   Hold Timing Library  (Min): $FAST_LIB"
puts "   Capacitance Table (Cap):    $CAP_TABLE"
puts "   SDC Constraints Mode:       $SDC_FILE"
puts "=================================================================="

# ------------------------------------------------------------------------------
# 1. RC Corner Definitions (Capacitance via CapTable)
# ------------------------------------------------------------------------------
# Max RC corner: 125C operating temperature for setup worst-case analysis
create_rc_corner -name rc_corner_max \
    -T 125 \
    -cap_table "$CAP_TABLE" \
    -preRoute_res 1.0 -preRoute_cap 1.0 \
    -postRoute_res 1.0 -postRoute_cap 1.0 -postRoute_xcap 1.0

# Min RC corner: -40C operating temperature for hold fast-race analysis
create_rc_corner -name rc_corner_min \
    -T -40 \
    -cap_table "$CAP_TABLE" \
    -preRoute_res 1.0 -preRoute_cap 1.0 \
    -postRoute_res 1.0 -postRoute_cap 1.0 -postRoute_xcap 1.0

# ------------------------------------------------------------------------------
# 2. Timing Library Sets
# ------------------------------------------------------------------------------
# Setup timing library set using slow.lib
create_library_set -name slow_lib_set -timing [list "$SLOW_LIB"]

# Hold timing library set using fast.lib
create_library_set -name fast_lib_set -timing [list "$FAST_LIB"]

# ------------------------------------------------------------------------------
# 3. Constraint Modes
# ------------------------------------------------------------------------------
create_constraint_mode -name default_constraint_mode -sdc_files [list "$SDC_FILE"]

# ------------------------------------------------------------------------------
# 4. Delay Corners (Mapping Library Set to RC Interconnect Corner)
# ------------------------------------------------------------------------------
# Max delay corner for Setup optimization & analysis
create_delay_corner -name delay_corner_max \
    -library_set slow_lib_set \
    -rc_corner rc_corner_max

# Min delay corner for Hold optimization & analysis
create_delay_corner -name delay_corner_min \
    -library_set fast_lib_set \
    -rc_corner rc_corner_min

# ------------------------------------------------------------------------------
# 5. Analysis Views
# ------------------------------------------------------------------------------
# Setup Analysis View
create_analysis_view -name setup_view \
    -constraint_mode default_constraint_mode \
    -delay_corner delay_corner_max

# Hold Analysis View
create_analysis_view -name hold_view \
    -constraint_mode default_constraint_mode \
    -delay_corner delay_corner_min

# ------------------------------------------------------------------------------
# 6. Set Active Analysis Views
# ------------------------------------------------------------------------------
set_analysis_view -setup [list setup_view] -hold [list hold_view]
puts "INFO: [MMMC] Active analysis views configured: -setup setup_view -hold hold_view"
