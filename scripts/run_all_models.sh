#!/usr/bin/env bash
# run_all_models.sh — Unified Simulation Runner for all 3 Architectural Models
# Supports both Verilator and Icarus Verilog

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SIM_TOOL="${1:-verilator}" # Default to verilator, or pass "iverilog"

echo "=================================================================="
echo " [PolyFlow-NPU] Running Complete Architectural Exploration Testsuite"
echo " Simulation Tool: $SIM_TOOL"
echo "=================================================================="

run_model_1() {
    echo -e "\n>>> [MODEL 1] Dataflow Switching (Sequential, Single Tenant) <<<"
    cd "$ROOT_DIR/models/dataflow_switching"
    if [ "$SIM_TOOL" = "verilator" ]; then
        verilator --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
            rtl/dfs_pe.v rtl/dfs_array.v rtl/dfs_top.v tb/dfs_top_tb.v \
            --top-module dfs_top_tb -o Vdfs_top_tb > /dev/null
        ./obj_dir/Vdfs_top_tb
    else
        iverilog -g2012 -o tb/dfs_top_tb.vvp rtl/*.v tb/dfs_top_tb.v
        vvp tb/dfs_top_tb.vvp
    fi
}

run_model_2() {
    echo -e "\n>>> [MODEL 2] Spatial Fission (Homogeneous WS Multi-Tenant) <<<"
    cd "$ROOT_DIR/models/spatial_fission"
    if [ "$SIM_TOOL" = "verilator" ]; then
        verilator --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
            rtl/sfa_pe.v rtl/sfa_fission_decoder.v rtl/sfa_array.v \
            rtl/sfa_otp_fsm.v rtl/sfa_bank_scrub.v rtl/sfa_eppa.v rtl/sfa_top.v \
            tb/sfa_top_tb.v --top-module sfa_top_tb -o Vsfa_top_tb > /dev/null
        ./obj_dir/Vsfa_top_tb
    else
        iverilog -g2012 -o tb/sfa_top_tb.vvp rtl/*.v tb/sfa_top_tb.v
        vvp tb/sfa_top_tb.vvp
    fi
}

run_model_3() {
    echo -e "\n>>> [MODEL 3] Heterogeneous Fission (PolyFlow-NPU / Novel Proposed) <<<"
    cd "$ROOT_DIR/models/heterogeneous_fission"
    if [ "$SIM_TOOL" = "verilator" ]; then
        verilator --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
            rtl/hdf_pe.v rtl/hdf_fission_decoder.v rtl/hdf_array_grid.v \
            rtl/eppa_arbiter.v rtl/otp_token_fsm.v rtl/pod_bank_scrub.v rtl/hdf_top.v \
            tb/hdf_top_tb.v --top-module hdf_top_tb -o Vhdf_top_tb > /dev/null
        ./obj_dir/Vhdf_top_tb
    else
        iverilog -g2012 -o tb/hdf_top_tb.vvp rtl/*.v tb/hdf_top_tb.v
        vvp tb/hdf_top_tb.vvp
    fi
}

run_model_1
run_model_2
run_model_3

echo "=================================================================="
echo " [SUCCESS] ALL THREE MODELS PASSED VERIFICATION CLEANLY!"
echo "=================================================================="
