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

declare -a SUMMARY_ROWS=()
TOTAL_MODELS=0
PASSED_MODELS=0

run_model_suite() {
    local base_dir="$1"
    local label="$2"

    echo "=================================================================="
    echo " >>> Running Suite: $label ($base_dir) <<<"
    echo "=================================================================="

    local -a models=(
        "dataflow_switching:dfs_top_tb:Dataflow Switching"
        "spatial_fission:sfa_top_tb:Spatial Fission"
        "heterogeneous_fission:hdf_top_tb:PolyFlow-NPU (HDF)"
    )

    for entry in "${models[@]}"; do
        IFS=":" read -r model_dir tb_module short_name <<< "$entry"
        echo -e "\n>>> [$short_name] [$label] <<<"
        cd "$base_dir/$model_dir"

        local log_file="/tmp/${tb_module}_${label}_run.log"
        local sim_status="PASS"
        local err_count="0"

        TOTAL_MODELS=$((TOTAL_MODELS + 1))

        set +e
        if [ "$SIM_TOOL" = "verilator" ]; then
            verilator -j "$(nproc)" --binary --timing -Wall -Itb -Itb/tests \
                -MAKEFLAGS "-j$(nproc) OPT_FAST=-O1" \
                rtl/*.sv "tb/${tb_module}.sv" --top-module "$tb_module" -o "V${tb_module}" > /dev/null 2>&1
            "./obj_dir/V${tb_module}" +TEST="$TEST_NAME" 2>&1 | tee "$log_file"
            cmd_rc=${PIPESTATUS[0]}
        elif [ "$SIM_TOOL" = "xrun" ] || [ "$SIM_TOOL" = "cadence" ]; then
            make run GUI=0 TEST="$TEST_NAME" 2>&1 | tee "$log_file"
            cmd_rc=${PIPESTATUS[0]}
        elif [ "$SIM_TOOL" = "iverilog" ]; then
            mkdir -p output
            iverilog -g2012 -I tb -I tb/tests -o "output/${tb_module}.vvp" rtl/*.sv "tb/${tb_module}.sv"
            vvp "output/${tb_module}.vvp" +TEST="$TEST_NAME" 2>&1 | tee "$log_file"
            cmd_rc=${PIPESTATUS[0]}
        else
            echo "Error: Unknown simulation tool '$SIM_TOOL'. Choose 'verilator', 'iverilog', or 'xrun'/'cadence'."
            exit 1
        fi
        set -e

        # Parse coverage from log
        local cov
        cov=$(grep "TOTAL FUNCTIONAL COVERAGE" "$log_file" | awk -F':' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | tr -s ' ' || true)
        if [ -z "$cov" ]; then
            cov="N/A"
        fi

        if [ "$cmd_rc" -eq 0 ] && grep -q "\[SUCCESS\]" "$log_file"; then
            sim_status="PASS"
            err_count="0"
            PASSED_MODELS=$((PASSED_MODELS + 1))
        else
            sim_status="FAIL"
            err_count=$(grep -oE "[0-9]+ ERRORS" "$log_file" | head -n1 | awk '{print $1}' || echo "1+")
            if [ -z "$err_count" ]; then err_count="1+"; fi
        fi

        SUMMARY_ROWS+=("${short_name}|${label}|${SIM_TOOL}|${sim_status}|${err_count}|${cov}")
        rm -f "$log_file"
    done
}

if [ "$VARIANT" = "pipelined" ] || [ "$VARIANT" = "all" ]; then
    run_model_suite "$ROOT_DIR/models/pipelined" "PIPELINED"
fi

if [ "$VARIANT" = "non_pipelined" ] || [ "$VARIANT" = "all" ]; then
    run_model_suite "$ROOT_DIR/models/non_pipelined" "NON-PIPELINED"
fi

echo -e "\n========================================================================================="
echo "                            ARCHITECTURAL REGRESSION SUMMARY"
echo "========================================================================================="
printf " %-23s %-15s %-11s %-8s %-8s %-20s\n" "Model" "Variant" "Simulator" "Status" "Errors" "Coverage"
echo "-----------------------------------------------------------------------------------------"
for row in "${SUMMARY_ROWS[@]}"; do
    IFS="|" read -r m_name m_var m_tool m_stat m_err m_cov <<< "$row"
    printf " %-23s %-15s %-11s %-8s %-8s %-20s\n" "$m_name" "$m_var" "$m_tool" "$m_stat" "$m_err" "$m_cov"
done
echo "========================================================================================="

if [ "$PASSED_MODELS" -eq "$TOTAL_MODELS" ] && [ "$TOTAL_MODELS" -gt 0 ]; then
    echo " [SUCCESS] $PASSED_MODELS / $TOTAL_MODELS Models PASSED CLEANLY (All Tests & Coverage Verified)!"
    echo "========================================================================================="
    exit 0
else
    echo " [FAILURE] Only $PASSED_MODELS / $TOTAL_MODELS Models passed cleanly."
    echo "========================================================================================="
    exit 1
fi
