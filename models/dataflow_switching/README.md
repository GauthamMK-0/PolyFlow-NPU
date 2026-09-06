# Model 1: Dataflow Switching Architecture

## Overview
This directory contains the standalone **Dataflow Switching Model** (corresponding to **Configuration B** in `evaluation_framework.md` / ReDas-style architecture).

### Architectural Characteristics
* **Single Tenant:** A single workload occupies the entire physical PE array ($M \times N$).
* **Runtime Dataflow Reconfiguration:** Allows per-tile switching across three core dataflows:
  1. `2'b00` — **Weight-Stationary (WS):** Best for Convolution and Fully-Connected layers with high filter reuse.
  2. `2'b01` — **Output-Stationary (OS):** Optimal for Self-Attention matrix multiplications ($Q \cdot K^T$ and $S \cdot V$) where both inputs are transient activations.
  3. `2'b10` — **Input-Stationary (IS):** Optimal for Depthwise-Separable convolutions where activations fan out across multiple filter taps.
* **No Spatial Fission:** Demonstrates dataflow flexibility in isolation without concurrent multi-tenancy or array partitioning.

---

## Directory Structure
```
models/dataflow_switching/
├── rtl/
│   ├── dfs_pe.sv      # Heterogeneous Processing Element with WS/OS/IS multiplexing
│   ├── dfs_array.sv   # 2D Systolic Array Grid
│   └── dfs_top.sv     # Top-level array controller
├── tb/
│   └── dfs_top_tb.sv  # SystemVerilog testbench validating sequential tile switching
└── README.md
```

---

## Verification & Simulation

### Using Verilator
```bash
cd models/dataflow_switching
verilator --binary --timing -Wall -Wno-fatal \
    rtl/dfs_pe.sv rtl/dfs_array.sv rtl/dfs_top.sv tb/dfs_top_tb.sv \
    --top-module dfs_top_tb -o Vdfs_top_tb
./obj_dir/Vdfs_top_tb
```

### Using Icarus Verilog (Alternative)
```bash
cd models/dataflow_switching
iverilog -g2012 -o tb/dfs_top_tb.vvp rtl/*.sv tb/dfs_top_tb.sv
vvp tb/dfs_top_tb.vvp
```
