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
        verilator --binary --timing -Wall \
            rtl/dfs_pe.sv rtl/dfs_array.sv rtl/dfs_top.sv tb/dfs_top_tb.sv \
            --top-module dfs_top_tb -o Vdfs_top_tb > /dev/null
        ./obj_dir/Vdfs_top_tb
    else
        iverilog -g2012 -o tb/dfs_top_tb.vvp rtl/*.sv tb/dfs_top_tb.sv
        vvp tb/dfs_top_tb.vvp
    fi
}

run_model_2() {
    echo -e "\n>>> [MODEL 2] Spatial Fission (Homogeneous WS Multi-Tenant) <<<"
    cd "$ROOT_DIR/models/spatial_fission"
    if [ "$SIM_TOOL" = "verilator" ]; then
        verilator --binary --timing -Wall \
            rtl/sfa_pe.sv rtl/sfa_fission_decoder.sv rtl/sfa_array.sv \
            rtl/sfa_otp_fsm.sv rtl/sfa_bank_scrub.sv rtl/sfa_eppa.sv rtl/sfa_top.sv \
            tb/sfa_top_tb.sv --top-module sfa_top_tb -o Vsfa_top_tb > /dev/null
        ./obj_dir/Vsfa_top_tb
    else
        iverilog -g2012 -o tb/sfa_top_tb.vvp rtl/*.sv tb/sfa_top_tb.sv
        vvp tb/sfa_top_tb.vvp
    fi
}

run_model_3() {
    echo -e "\n>>> [MODEL 3] Heterogeneous Fission (PolyFlow-NPU / Novel Proposed) <<<"
    cd "$ROOT_DIR/models/heterogeneous_fission"
    if [ "$SIM_TOOL" = "verilator" ]; then
        verilator --binary --timing -Wall \
            rtl/hdf_pe.sv rtl/hdf_fission_decoder.sv rtl/hdf_array_grid.sv \
            rtl/eppa_arbiter.sv rtl/otp_token_fsm.sv rtl/pod_bank_scrub.sv rtl/hdf_top.sv \
            tb/hdf_top_tb.sv --top-module hdf_top_tb -o Vhdf_top_tb > /dev/null
        ./obj_dir/Vhdf_top_tb
    else
        iverilog -g2012 -o tb/hdf_top_tb.vvp rtl/*.sv tb/hdf_top_tb.sv
        vvp tb/hdf_top_tb.vvp
    fi
}

run_model_1
run_model_2
run_model_3

echo "=================================================================="
echo " [SUCCESS] ALL THREE MODELS PASSED VERIFICATION CLEANLY!"
echo "=================================================================="
