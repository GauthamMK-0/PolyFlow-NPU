#!/usr/bin/env bash
# run_all_models.sh — Unified Simulation Runner for Pipelined and Non-Pipelined Models
# Supports Verilator, Cadence Xcelium (xrun), and Icarus Verilog

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SIM_TOOL="${1:-verilator}"      # verilator | iverilog | xrun | cadence
VARIANT="${2:-all}"            # all | pipelined | non_pipelined
SCALE="${3:-4x4}"              # 4x4 | 8x8 | 16x16 | all

echo "=================================================================="
echo " [PolyFlow-NPU] Running Architectural Exploration Testsuite"
echo " Simulation Tool: $SIM_TOOL | Variant: $VARIANT | Scale: $SCALE"
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

    local -a models=()
    if [ "$label" = "PIPELINED" ]; then
        if [ "$SCALE" = "4x4" ]; then
            models+=(
                "dataflow_switching:dfs_top_tb:Dataflow Switching (4x4)"
                "spatial_fission:sfa_top_tb:Spatial Fission (4x4)"
                "heterogeneous_fission:hdf_top_tb:PolyFlow-NPU HDF (4x4)"
            )
        elif [ "$SCALE" = "8x8" ]; then
            models+=(
                "dataflow_switching:dfs_top_8x8_tb:Dataflow Switching (8x8)"
                "spatial_fission:sfa_top_8x8_tb:Spatial Fission (8x8)"
                "heterogeneous_fission:hdf_top_8x8_tb:PolyFlow-NPU HDF (8x8)"
            )
        elif [ "$SCALE" = "16x16" ]; then
            models+=(
                "dataflow_switching:dfs_top_16x16_tb:Dataflow Switching (16x16)"
                "spatial_fission:sfa_top_16x16_tb:Spatial Fission (16x16)"
                "heterogeneous_fission:hdf_top_16x16_tb:PolyFlow-NPU HDF (16x16)"
            )
        elif [ "$SCALE" = "all" ]; then
            models+=(
                "dataflow_switching:dfs_top_tb:Dataflow Switching (4x4)"
                "dataflow_switching:dfs_top_8x8_tb:Dataflow Switching (8x8)"
                "dataflow_switching:dfs_top_16x16_tb:Dataflow Switching (16x16)"
                "spatial_fission:sfa_top_tb:Spatial Fission (4x4)"
                "spatial_fission:sfa_top_8x8_tb:Spatial Fission (8x8)"
                "spatial_fission:sfa_top_16x16_tb:Spatial Fission (16x16)"
                "heterogeneous_fission:hdf_top_tb:PolyFlow-NPU HDF (4x4)"
                "heterogeneous_fission:hdf_top_8x8_tb:PolyFlow-NPU HDF (8x8)"
                "heterogeneous_fission:hdf_top_16x16_tb:PolyFlow-NPU HDF (16x16)"
            )
        fi
    else
        # Non-pipelined baseline (4x4 only)
        models+=(
            "dataflow_switching:dfs_top_tb:Dataflow Switching (4x4)"
            "spatial_fission:sfa_top_tb:Spatial Fission (4x4)"
            "heterogeneous_fission:hdf_top_tb:PolyFlow-NPU HDF (4x4)"
        )
    fi

    for entry in "${models[@]}"; do
        IFS=":" read -r model_dir tb_module short_name <<< "$entry"
        echo -e "\n>>> [$short_name] [$label] <<<"
        cd "$base_dir/$model_dir"

        local log_file="/tmp/${tb_module}_${label}_run.log"
        local sim_status="PASS"
        local err_count="0"

        TOTAL_MODELS=$((TOTAL_MODELS + 1))

        set +e
        local item_scale="4x4"
        if [[ "$tb_module" =~ "16x16" ]]; then
            item_scale="16x16"
        elif [[ "$tb_module" =~ "8x8" ]]; then
            item_scale="8x8"
        fi

        if [ "$SIM_TOOL" = "verilator" ]; then
            local v_obj_dir="obj_dir/${item_scale}"
            mkdir -p "$v_obj_dir"
            verilator -j "$(nproc)" --binary --timing -Wall -Itb \
                --Mdir "$v_obj_dir" \
                -MAKEFLAGS "-j$(nproc) OPT_FAST=-O1" \
                rtl/*.sv "tb/${tb_module}.sv" --top-module "$tb_module" -o "V${tb_module}" > /dev/null 2>&1
            "./${v_obj_dir}/V${tb_module}" 2>&1 | tee "$log_file"
            cmd_rc=${PIPESTATUS[0]}
        elif [ "$SIM_TOOL" = "xrun" ] || [ "$SIM_TOOL" = "cadence" ]; then
            make run SCALE="$item_scale" GUI=0 2>&1 | tee "$log_file"
            cmd_rc=${PIPESTATUS[0]}
        elif [ "$SIM_TOOL" = "iverilog" ]; then
            mkdir -p "output/${item_scale}"
            iverilog -g2012 -I tb -o "output/${item_scale}/${tb_module}.vvp" rtl/*.sv "tb/${tb_module}.sv"
            if [ "$item_scale" = "4x4" ]; then
                mkdir -p output
                cp -f "output/${item_scale}/${tb_module}.vvp" "output/${tb_module}.vvp"
            fi
            vvp "output/${item_scale}/${tb_module}.vvp" 2>&1 | tee "$log_file"
            cmd_rc=${PIPESTATUS[0]}
        else
            echo "Error: Unknown simulation tool '$SIM_TOOL'. Choose 'verilator', 'iverilog', or 'xrun'/'cadence'."
            exit 1
        fi
        set -e

        if [ "$cmd_rc" -eq 0 ] && grep -q "\[SUCCESS\]" "$log_file"; then
            sim_status="PASS"
            err_count="0"
            PASSED_MODELS=$((PASSED_MODELS + 1))
        else
            sim_status="FAIL"
            err_count=$(grep -oE "[0-9]+ ERRORS" "$log_file" | head -n1 | awk '{print $1}' || echo "1+")
            if [ -z "$err_count" ]; then err_count="1+"; fi
        fi

        SUMMARY_ROWS+=("${short_name}|${label}|${SIM_TOOL}|${sim_status}|${err_count}")
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
printf " %-25s %-16s %-12s %-10s %-8s\n" "Model" "Variant" "Simulator" "Status" "Errors"
echo "-----------------------------------------------------------------------------------------"
for row in "${SUMMARY_ROWS[@]}"; do
    IFS="|" read -r m_name m_var m_tool m_stat m_err <<< "$row"
    printf " %-25s %-16s %-12s %-10s %-8s\n" "$m_name" "$m_var" "$m_tool" "$m_stat" "$m_err"
done
echo "========================================================================================="

if [ "$PASSED_MODELS" -eq "$TOTAL_MODELS" ] && [ "$TOTAL_MODELS" -gt 0 ]; then
    echo " [SUCCESS] $PASSED_MODELS / $TOTAL_MODELS Models PASSED CLEANLY!"
    echo "========================================================================================="
    exit 0
else
    echo " [FAILURE] Only $PASSED_MODELS / $TOTAL_MODELS Models passed cleanly."
    echo "========================================================================================="
    exit 1
fi
