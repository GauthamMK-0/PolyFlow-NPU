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
│   ├── dfs_pe.v       # Heterogeneous Processing Element with WS/OS/IS multiplexing
│   ├── dfs_array.v    # 2D Systolic Array Grid
│   └── dfs_top.v      # Top-level array controller
├── tb/
│   └── dfs_top_tb.v   # SystemVerilog testbench validating sequential tile switching
└── README.md
```

---

## Verification & Simulation

### Using Verilator
```bash
cd models/dataflow_switching
verilator --binary --timing -Wall -Wno-fatal \
    rtl/dfs_pe.v rtl/dfs_array.v rtl/dfs_top.v tb/dfs_top_tb.v \
    --top-module dfs_top_tb -o Vdfs_top_tb
./obj_dir/Vdfs_top_tb
```

### Using Icarus Verilog (Alternative)
```bash
cd models/dataflow_switching
iverilog -g2012 -o tb/dfs_top_tb.vvp rtl/*.v tb/dfs_top_tb.v
vvp tb/dfs_top_tb.vvp
```
