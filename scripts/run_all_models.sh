#!/usr/bin/env bash
# run_all_models.sh — Unified Simulation Runner for Pipelined and Non-Pipelined Models
# Supports Verilator, Cadence Xcelium (xrun), and Icarus Verilog

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SIM_TOOL="${1:-verilator}"      # verilator | iverilog | xrun | cadence
VARIANT="${2:-all}"            # all | pipelined | non_pipelined
TEST_NAME="${3:-ALL}"          # ALL | specific test name

echo "=================================================================="
echo " [PolyFlow-NPU] Running Complete Architectural Exploration Testsuite"
echo " Simulation Tool: $SIM_TOOL | Variant: $VARIANT | Test: $TEST_NAME"
echo "=================================================================="

run_model_suite() {
    local base_dir="$1"
    local label="$2"

    echo "=================================================================="
    echo " >>> Running Suite: $label ($base_dir) <<<"
    echo "=================================================================="

    local -a models=(
        "dataflow_switching:dfs_top_tb:MODEL 1: Dataflow Switching (Single-Tenant)"
        "spatial_fission:sfa_top_tb:MODEL 2: Spatial Fission (Homogeneous WS)"
        "heterogeneous_fission:hdf_top_tb:MODEL 3: Heterogeneous Fission (PolyFlow-NPU)"
    )

    for entry in "${models[@]}"; do
        IFS=":" read -r model_dir tb_module desc <<< "$entry"
        echo -e "\n>>> [$desc] [$label] <<<"
        cd "$base_dir/$model_dir"

        if [ "$SIM_TOOL" = "verilator" ]; then
            verilator -j "$(nproc)" --binary --timing -Wall -Itb -Itb/tests \
                rtl/*.sv "tb/${tb_module}.sv" --top-module "$tb_module" -o "V${tb_module}" > /dev/null
            "./obj_dir/V${tb_module}" +TEST="$TEST_NAME"
        elif [ "$SIM_TOOL" = "xrun" ] || [ "$SIM_TOOL" = "cadence" ]; then
            make run GUI=0 TEST="$TEST_NAME"
        elif [ "$SIM_TOOL" = "iverilog" ]; then
            iverilog -g2012 -I tb -I tb/tests -o "tb/${tb_module}.vvp" rtl/*.sv "tb/${tb_module}.sv"
            vvp "tb/${tb_module}.vvp" +TEST="$TEST_NAME"
        else
            echo "Error: Unknown simulation tool '$SIM_TOOL'. Choose 'verilator', 'iverilog', or 'xrun'/'cadence'."
            exit 1
        fi
    done
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
