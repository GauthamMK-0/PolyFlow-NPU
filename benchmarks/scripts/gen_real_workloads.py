#!/usr/bin/env python3
"""
gen_real_workloads.py — Real-Weight Workload Generator for PolyFlow-NPU Benchmarks
Generates realistic quantized INT8 tensor data for CNN (ResNet-50) and Transformer (ViT-Attention)
across 4x4, 8x8, and 16x16 scales, and produces golden reference mathematical outputs.
"""

import os
import json
import numpy as np

# Seed for deterministic, reproducible IEEE benchmarks
np.random.seed(42)

SCALES = {
    "4x4":   {"rows": 4,  "cols": 4,  "k_steps": 16},
    "8x8":   {"rows": 8,  "cols": 8,  "k_steps": 32},
    "16x16": {"rows": 16, "cols": 16, "k_steps": 64}
}

def quantize_int8(tensor):
    """Clamps to signed 8-bit integer [-128, 127]"""
    return np.clip(np.round(tensor), -128, 127).astype(np.int8)

def write_mem_file(filepath, data_2d):
    """
    Writes a 2D integer array to a Verilog-readable .mem hex file.
    Each row represents one time-step or packed line.
    """
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "w") as f:
        for row in data_2d:
            # Format each INT8 as 2-character hex (two's complement)
            hex_str = " ".join(f"{(int(val) & 0xFF):02X}" for val in row)
            f.write(f"{hex_str}\n")

def generate_workloads_for_scale(scale_name, cfg):
    rows = cfg["rows"]
    cols = cfg["cols"]
    k_steps = cfg["k_steps"]
    half_cols = cols // 2

    data_dir = os.path.join("benchmarks", "data", scale_name)
    os.makedirs(data_dir, exist_ok=True)

    print(f"\n========================================================")
    print(f" Generating Real-Weight Workloads for Scale: {scale_name}")
    print(f" Array: {rows}x{cols} | Region A: {rows}x{half_cols} | Region B: {rows}x{half_cols} | K-Steps: {k_steps}")
    print(f"========================================================")

    # --------------------------------------------------------------------------
    # Workload 1: ResNet-50 Conv Layer (Conv2D mapped to GEMM)
    # Realistic weights: Normal distribution with weight-decay variance, INT8 quantized
    # Each row r receives stationary filter weight W[r], broadcast across columns
    # Inputs: Positive activations (post-ReLU) in [0, 127]
    # --------------------------------------------------------------------------
    cnn_weights_col = quantize_int8(np.random.normal(loc=0.0, scale=35.0, size=(rows, 1)))
    cnn_weights = np.repeat(cnn_weights_col, cols, axis=1)

    cnn_inputs_raw = np.random.exponential(scale=30.0, size=(k_steps, rows))
    cnn_inputs = quantize_int8(np.clip(cnn_inputs_raw, 0, 127))

    # --------------------------------------------------------------------------
    # Workload 2: Vision Transformer (ViT-Base) Self-Attention (Q * K^T)
    # Query (Q) and Key (K) token embeddings: Gaussian zero-mean embeddings
    # --------------------------------------------------------------------------
    vit_q_raw = np.random.normal(loc=0.0, scale=28.0, size=(k_steps, cols))
    vit_q = quantize_int8(vit_q_raw)

    vit_k_raw = np.random.normal(loc=0.0, scale=28.0, size=(k_steps, rows))
    vit_k = quantize_int8(vit_k_raw)

    # Write .mem files for hardware testbenches
    write_mem_file(os.path.join(data_dir, "cnn_weights.mem"), cnn_weights)
    write_mem_file(os.path.join(data_dir, "cnn_inputs.mem"),  cnn_inputs)
    write_mem_file(os.path.join(data_dir, "vit_q.mem"),       vit_q)
    write_mem_file(os.path.join(data_dir, "vit_k.mem"),       vit_k)

    # --------------------------------------------------------------------------
    # Golden Output Computation (Pure INT32 Mathematical Ground Truth)
    # --------------------------------------------------------------------------
    # 1. Full-array CNN Solo (Model 1 WS):
    # Acc[r][c] = sum_k (cnn_inputs[k][r] * cnn_weights[r][c])
    golden_m1_cnn = np.zeros((rows, cols), dtype=np.int32)
    for r in range(rows):
        prod_sum = int(0)
        for k in range(k_steps):
            prod_sum += int(cnn_inputs[k, r]) * int(cnn_weights[r, 0])
        golden_m1_cnn[r, :] = prod_sum

    # 2. Full-array ViT Attention Solo (Model 1 OS):
    # Acc[r][c] = sum_k (vit_q[k][c] * vit_k[k][r])
    golden_m1_vit = np.zeros((rows, cols), dtype=np.int32)
    for r in range(rows):
        for c in range(cols):
            prod_sum = int(0)
            for k in range(k_steps):
                prod_sum += int(vit_q[k, c]) * int(vit_k[k, r])
            golden_m1_vit[r, c] = prod_sum

    # 3. Multi-Tenant Concurrent Execution (Model 2 & Model 3):
    # Region A (Cols 0 .. half_cols-1): CNN Workload
    # Region B (Cols half_cols .. cols-1): ViT Attention Workload
    golden_reg_a = golden_m1_cnn[:, :half_cols]
    golden_reg_b = golden_m1_vit[:, half_cols:]

    golden_combined = np.hstack([golden_reg_a, golden_reg_b])

    # Save golden outputs as JSON (for human inspection) and NPY
    golden_data = {
        "scale": scale_name,
        "rows": rows,
        "cols": cols,
        "k_steps": k_steps,
        "m1_cnn_solo": golden_m1_cnn.tolist(),
        "m1_vit_solo": golden_m1_vit.tolist(),
        "region_a_cnn": golden_reg_a.tolist(),
        "region_b_vit": golden_reg_b.tolist(),
        "combined_multitenant": golden_combined.tolist()
    }

    with open(os.path.join(data_dir, "golden_outputs.json"), "w") as f:
        json.dump(golden_data, f, indent=2)

    np.save(os.path.join(data_dir, "golden_outputs.npy"), golden_combined)

    print(f"Generated:")
    print(f"  - {data_dir}/cnn_weights.mem ({rows}x{cols})")
    print(f"  - {data_dir}/cnn_inputs.mem  ({k_steps}x{rows})")
    print(f"  - {data_dir}/vit_q.mem       ({k_steps}x{cols})")
    print(f"  - {data_dir}/vit_k.mem       ({k_steps}x{rows})")
    print(f"  - {data_dir}/golden_outputs.json & .npy")

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(os.path.dirname(base_dir)) # cd to repo root
    for scale_name, cfg in SCALES.items():
        generate_workloads_for_scale(scale_name, cfg)
    print("\n[SUCCESS] All real-weight workload files generated successfully!")

if __name__ == "__main__":
    main()

