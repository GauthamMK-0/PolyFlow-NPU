# PolyFlow-NPU Real-Workload Throughput & Accuracy Benchmark Suite

## Overview
This directory contains the automated **Hardware/Software Co-Verification and Empirical Throughput Benchmarking Suite** for PolyFlow-NPU. It replaces theoretical approximations with **100% empirical, cycle-accurate RTL measurements** obtained by driving real quantized neural network weights through the synthesized hardware models.

---

## 1. Workload Description
The benchmark co-executes two distinct neural network operators representing multi-modal multi-tenancy:
1. **Tenant 1 (Convolutional CNN):** ResNet-50 Convolutional Layer (`res4a_branch2b`).
   - Mapped to GEMM: Stationary filter weights $W_{\text{conv}}$ + streaming activation vectors $X_{\text{conv}}$.
   - **Optimal Dataflow:** **Weight-Stationary (WS)**.
2. **Tenant 2 (Transformer Self-Attention):** Vision Transformer (ViT-Base) / BERT Self-Attention ($Q \cdot K^T$).
   - Mapped to GEMM: Transient Query vectors $Q$ + transient Key vectors $K$.
   - **Optimal Dataflow:** **Output-Stationary (OS)**.

All weights and activations are quantized to **signed INT8 (`[-128, +127]`)** with 32-bit accumulation (`INT32`).

---

## 2. Directory Structure
```
benchmarks/
├── data/                             # Real INT8 quantized weights & golden models
│   ├── 4x4/                          # 4x4 tile vectors & golden reference
│   ├── 8x8/                          # 8x8 tile vectors & golden reference
│   └── 16x16/                        # 16x16 tile vectors & golden reference
├── tb/                               # Cycle-accurate SystemVerilog benchmark testbenches
│   ├── cosim_model1_dfs_tb.sv        # Model 1 (ReDas: Sequential WS -> OS)
│   ├── cosim_model2_sfa_tb.sv        # Model 2 (Planaria: Concurrent split, forced WS)
│   └── cosim_model3_hdf_tb.sv        # Model 3 (PolyFlow-NPU: Concurrent split, WS + OS)
├── scripts/                          # Automation & verification scripts
│   ├── gen_real_workloads.py         # Generates real quantized weights across scales
│   ├── verify_accuracy.py            # Validates 100% bit-exact equivalence vs. Python NumPy
│   └── run_throughput_benchmark.py   # Runs all 3 scales & generates IEEE comparison tables
├── results/                          # Partitioned hardware traces & reports
│   ├── 4x4/                          # 4x4 cycle traces, raw dumps, and metrics
│   ├── 8x8/                          # 8x8 cycle traces, raw dumps, and metrics
│   ├── 16x16/                        # 16x16 cycle traces, raw dumps, and metrics
│   └── throughput_summary.md         # Final paper-ready IEEE comparison table
├── Makefile                          # One-command automation
└── README.md                         # This file
```

---

## 3. How to Run the Benchmark
From the repository root or `benchmarks/` directory:

```bash
# Run full benchmark across all 3 scales (4x4, 8x8, 16x16):
cd benchmarks
make run

# Or run individual scales:
make run-4x4
make run-8x8
make run-16x16

# Verify bit-exact accuracy:
make verify
```

---

## 4. Evaluated Metrics
1. **Makespan ($T_{\text{total}}$):** Exact clock cycles from first tile issue to final accumulator drain.
2. **Sustained Throughput ($\text{GOPS}$):** Real arithmetic operations executed per second at 200 MHz:
   $$\text{GOPS} = \frac{2 \times \text{Total Valid MACs}}{T_{\text{total}} \times 5.0\text{ ns}}$$
3. **PE Compute Utilization ($U_{\text{PE}}$):**
   $$U_{\text{PE}} = \frac{\text{Sustained GOPS}}{\text{Peak GOPS}} \times 100\%$$
4. **Multi-Tenant Weighted Speedup ($WS$):**
   $$WS = \frac{T_{\text{CNN}}^{\text{solo}}}{T_{\text{Region A}}} + \frac{T_{\text{ViT}}^{\text{solo}}}{T_{\text{Region B}}}$$
5. **Numerical Accuracy:** Bit-exact match rate ($100.00\%$), Mean Squared Error ($\text{MSE} = 0.000$), and Cosine Similarity ($1.000000$).

