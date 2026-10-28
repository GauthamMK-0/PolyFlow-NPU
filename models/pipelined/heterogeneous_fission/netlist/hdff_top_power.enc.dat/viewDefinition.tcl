if {![namespace exists ::IMEX]} { namespace eval ::IMEX {} }
set ::IMEX::dataVar [file dirname [file normalize [info script]]]
set ::IMEX::libVar ${::IMEX::dataVar}/libs

set _min_lib [expr {[file exists "${::IMEX::libVar}/mmmc/fast.lib"] ? "${::IMEX::libVar}/mmmc/fast.lib" : "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/fast.lib"}]
set _max_lib [expr {[file exists "${::IMEX::libVar}/mmmc/slow.lib"] ? "${::IMEX::libVar}/mmmc/slow.lib" : "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib"}]
set _captbl  [expr {[file exists "${::IMEX::libVar}/mmmc/gpdk090.lef.extended.CapTbl"] ? "${::IMEX::libVar}/mmmc/gpdk090.lef.extended.CapTbl" : "/home/cadence/install/FOUNDRY/digital/90nm/dig/captable/gpdk090.lef.extended.CapTbl"}]

create_library_set -name MIN\
   -timing\
    [list $_min_lib]
create_library_set -name MAX\
   -timing\
    [list $_max_lib]
create_rc_corner -name CAP\
   -cap_table $_captbl\
   -preRoute_res 1\
   -postRoute_res 1\
   -preRoute_cap 1\
   -postRoute_cap 1\
   -postRoute_xcap 1\
   -preRoute_clkres 0\
   -preRoute_clkcap 0
create_delay_corner -name SET_MAX\
   -library_set MAX\
   -rc_corner CAP
create_delay_corner -name HOD_MIN\
   -library_set MIN\
   -rc_corner CAP
create_constraint_mode -name SDC\
   -sdc_files\
    [list /dev/null]
create_analysis_view -name HOD -constraint_mode SDC -delay_corner HOD_MIN
create_analysis_view -name SETUP -constraint_mode SDC -delay_corner SET_MAX
set_analysis_view -setup [list SETUP] -hold [list HOD]
