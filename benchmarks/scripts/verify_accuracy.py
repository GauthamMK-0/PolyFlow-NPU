#!/usr/bin/env python3
"""
verify_accuracy.py — Hardware/Software Co-Verification & Bit-Exact Accuracy Checker
Compares raw RTL hardware accumulator dumps against Python NumPy golden mathematical models.
Computes Bit-Exact Match Rate (%), Mean Absolute Error (MAE), Mean Squared Error (MSE), and Cosine Similarity.
"""

import os
import sys
import json
import numpy as np

def load_matrix_txt(filepath):
    """Loads whitespace-delimited integer matrix from file."""
    if not os.path.exists(filepath):
        return None
    matrix = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                matrix.append([int(x) for x in line.split()])
    return np.array(matrix, dtype=np.int32)

def evaluate_accuracy(hw_mat, golden_mat, label):
    """Evaluates numerical parity between hardware and golden software outputs."""
    if hw_mat is None or golden_mat is None:
        print(f"  [SKIPPED] {label}: Output file missing.")
        return False, {}

    if hw_mat.shape != golden_mat.shape:
        print(f"  [FAIL] {label}: Shape mismatch! HW: {hw_mat.shape}, Golden: {golden_mat.shape}")
        return False, {}

    total_elements = hw_mat.size
    matching_elements = int(np.sum(hw_mat == golden_mat))
    match_rate = (matching_elements / total_elements) * 100.0

    diff = hw_mat.astype(np.float64) - golden_mat.astype(np.float64)
    mae = float(np.mean(np.abs(diff)))
    mse = float(np.mean(diff ** 2))

    # Cosine similarity (cast to float64 to prevent int32 dot-product overflow)
    hw_f64 = hw_mat.flatten().astype(np.float64)
    gold_f64 = golden_mat.flatten().astype(np.float64)
    norm_hw = np.linalg.norm(hw_f64)
    norm_gold = np.linalg.norm(gold_f64)
    if norm_hw > 0 and norm_gold > 0:
        cos_sim = float(np.dot(hw_f64, gold_f64) / (norm_hw * norm_gold))
    else:
        cos_sim = 1.0 if np.array_equal(hw_mat, golden_mat) else 0.0

    passed = (matching_elements == total_elements) and (mse == 0.0)

    stats = {
        "label": label,
        "total_elements": total_elements,
        "matching_elements": matching_elements,
        "match_rate_pct": match_rate,
        "mae": mae,
        "mse": mse,
        "cosine_similarity": cos_sim,
        "status": "PASS (Bit-Exact 100%)" if passed else "FAIL"
    }

    status_str = "\033[92m[PASS: 100% BIT-EXACT]\033[0m" if passed else "\033[91m[FAIL]\033[0m"
    print(f"  {status_str} {label}")
    print(f"      Matched Elements: {matching_elements}/{total_elements} ({match_rate:.2f}%)")
    print(f"      Mean Squared Error (MSE): {mse:.6f} | Cosine Similarity: {cos_sim:.6f}")

    return passed, stats

def verify_scale(scale_name):
    data_dir = os.path.join("benchmarks", "data", scale_name)
    results_dir = os.path.join("benchmarks", "results", scale_name)

    golden_json_path = os.path.join(data_dir, "golden_outputs.json")
    if not os.path.exists(golden_json_path):
        print(f"Error: Golden reference not found at {golden_json_path}. Run gen_real_workloads.py first.")
        return False

    with open(golden_json_path, "r") as f:
        golden_data = json.load(f)

    golden_m1_cnn = np.array(golden_data["m1_cnn_solo"], dtype=np.int32)
    golden_m1_vit = np.array(golden_data["m1_vit_solo"], dtype=np.int32)
    golden_combined = np.array(golden_data["combined_multitenant"], dtype=np.int32)

    hw_m1_cnn = load_matrix_txt(os.path.join(results_dir, "m1_cnn_hw_output.txt"))
    hw_m1_vit = load_matrix_txt(os.path.join(results_dir, "m1_vit_hw_output.txt"))
    hw_m2_combined = load_matrix_txt(os.path.join(results_dir, "m2_multitenant_hw_output.txt"))
    hw_m3_combined = load_matrix_txt(os.path.join(results_dir, "m3_multitenant_hw_output.txt"))

    print(f"\n========================================================")
    print(f" Co-Verification & Accuracy Evaluation [Scale: {scale_name}]")
    print(f"========================================================")

    all_passed = True
    scale_stats = []

    # 1. Model 1 CNN Solo Verification
    p1, s1 = evaluate_accuracy(hw_m1_cnn, golden_m1_cnn, "Model 1: ResNet-50 CNN (Weight-Stationary)")
    all_passed = all_passed and p1
    if s1: scale_stats.append(s1)

    # 2. Model 1 ViT Solo Verification
    p2, s2 = evaluate_accuracy(hw_m1_vit, golden_m1_vit, "Model 1: ViT Attention (Output-Stationary)")
    all_passed = all_passed and p2
    if s2: scale_stats.append(s2)

    # 3. Model 2 Multi-Tenant Homogeneous Fission Verification
    p2m, s2m = evaluate_accuracy(hw_m2_combined, golden_combined, "Model 2: Planaria Homogeneous Fission (Region A: WS + Region B: Forced WS)")
    all_passed = all_passed and p2m
    if s2m: scale_stats.append(s2m)

    # 4. Model 3 Multi-Tenant Concurrent Execution Verification
    p3, s3 = evaluate_accuracy(hw_m3_combined, golden_combined, "Model 3: PolyFlow-NPU Concurrent Execution (Region A: WS + Region B: OS)")
    all_passed = all_passed and p3
    if s3: scale_stats.append(s3)

    # Dump verification summary JSON
    with open(os.path.join(results_dir, "accuracy_report.json"), "w") as f:
        json.dump(scale_stats, f, indent=2)

    return all_passed

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(os.path.dirname(base_dir)) # cd to repo root

    scales = ["4x4", "8x8", "16x16"]
    if len(sys.argv) > 1 and sys.argv[1] in scales:
        scales = [sys.argv[1]]

    total_passed = True
    for s in scales:
        res_dir = os.path.join("benchmarks", "results", s)
        if os.path.exists(res_dir) and any(f.endswith(".txt") for f in os.listdir(res_dir)):
            passed = verify_scale(s)
            total_passed = total_passed and passed

    print("\n========================================================")
    if total_passed:
        print(" \033[92m[SUCCESS] ALL VERIFIED HARDWARE OUTPUTS MATCH GOLDEN REFERENCE 100% BIT-FOR-BIT!\033[0m")
    else:
        print(" \033[91m[WARNING] Some verification checks failed or outputs were missing.\033[0m")
    print("========================================================\n")

if __name__ == "__main__":
    main()

