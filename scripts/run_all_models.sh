#!/usr/bin/env bash
# run_all_models.sh — Unified Simulation Runner for Pipelined and Non-Pipelined Models
# Supports both Verilator and Icarus Verilog

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SIM_TOOL="${1:-verilator}"      # verilator | iverilog
VARIANT="${2:-all}"            # all | pipelined | non_pipelined

echo "=================================================================="
echo " [PolyFlow-NPU] Running Complete Architectural Exploration Testsuite"
echo " Simulation Tool: $SIM_TOOL | Variant: $VARIANT"
echo "=================================================================="

run_model_suite() {
    local base_dir="$1"
    local label="$2"

    echo "=================================================================="
    echo " >>> Running Suite: $label ($base_dir) <<<"
    echo "=================================================================="

    echo -e "\n>>> [MODEL 1] Dataflow Switching (Single-Tenant) [$label] <<<"
    cd "$base_dir/dataflow_switching"
    if [ "$SIM_TOOL" = "verilator" ]; then
        verilator -j "$(nproc)" --binary --timing -Wall \
            rtl/dfs_pe.sv rtl/dfs_array.sv rtl/dfs_top.sv tb/dfs_top_tb.sv \
            --top-module dfs_top_tb -o Vdfs_top_tb > /dev/null
        ./obj_dir/Vdfs_top_tb
    else
        iverilog -g2012 -o tb/dfs_top_tb.vvp rtl/*.sv tb/dfs_top_tb.sv
        vvp tb/dfs_top_tb.vvp
    fi

    echo -e "\n>>> [MODEL 2] Spatial Fission (Homogeneous WS) [$label] <<<"
    cd "$base_dir/spatial_fission"
    if [ "$SIM_TOOL" = "verilator" ]; then
        verilator -j "$(nproc)" --binary --timing -Wall \
            rtl/sfa_pe.sv rtl/sfa_fission_decoder.sv rtl/sfa_array.sv \
            rtl/sfa_otp_fsm.sv rtl/sfa_bank_scrub.sv rtl/sfa_eppa.sv rtl/sfa_top.sv \
            tb/sfa_top_tb.sv --top-module sfa_top_tb -o Vsfa_top_tb > /dev/null
        ./obj_dir/Vsfa_top_tb
    else
        iverilog -g2012 -o tb/sfa_top_tb.vvp rtl/*.sv tb/sfa_top_tb.sv
        vvp tb/sfa_top_tb.vvp
    fi

    echo -e "\n>>> [MODEL 3] Heterogeneous Fission (PolyFlow-NPU) [$label] <<<"
    cd "$base_dir/heterogeneous_fission"
    if [ "$SIM_TOOL" = "verilator" ]; then
        verilator -j "$(nproc)" --binary --timing -Wall \
            rtl/hdf_pe.sv rtl/hdf_fission_decoder.sv rtl/hdf_array_grid.sv \
            rtl/eppa_arbiter.sv rtl/otp_token_fsm.sv rtl/pod_bank_scrub.sv rtl/hdf_top.sv \
            tb/hdf_top_tb.sv --top-module hdf_top_tb -o Vhdf_top_tb > /dev/null
        ./obj_dir/Vhdf_top_tb
    else
        iverilog -g2012 -o tb/hdf_top_tb.vvp rtl/*.sv tb/hdf_top_tb.sv
        vvp tb/hdf_top_tb.vvp
    fi
}

if [ "$VARIANT" = "pipelined" ] || [ "$VARIANT" = "all" ]; then
    run_model_suite "$ROOT_DIR/models/pipelined" "PIPELINED"
fi

if [ "$VARIANT" = "non_pipelined" ] || [ "$VARIANT" = "all" ]; then
    run_model_suite "$ROOT_DIR/models/non_pipelined" "NON-PIPELINED"
fi

echo -e "\n=================================================================="
echo " [SUCCESS] ALL SPECIFIED ARCHITECTURAL MODELS PASSED CLEANLY!"
echo "=================================================================="
