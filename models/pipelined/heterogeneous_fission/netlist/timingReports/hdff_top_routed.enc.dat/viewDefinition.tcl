create_library_set -name MIN\
   -timing\
    [list ../../../../../../../../cadence/install/FOUNDRY/digital/90nm/dig/lib/fast.lib]
create_library_set -name MAX\
   -timing\
    [list ../../../../../../../../cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib]
create_rc_corner -name CAP\
   -cap_table ../../../../../../../../cadence/install/FOUNDRY/digital/90nm/dig/captable/gpdk090.lef.extended.CapTbl\
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
