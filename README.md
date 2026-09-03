# PolyFlow-NPU: Polymorphic-Dataflow Fissionable Systolic Array
### *Concurrent Multi-Tenant Architecture with Independent Per-Region Dataflows*

[![Simulation](https://img.shields.io/badge/Simulation-Verilator%20%7C%20Icarus%20Verilog-brightgreen.svg)]()
[![Lint](https://img.shields.io/badge/Verilator%20Lint-0%20Errors%20%7C%200%20Warnings-blue.svg)]()
[![License](https://img.shields.io/badge/License-Academic%20Research-orange.svg)]()

---

## 1. Executive Summary & Core Novel Idea

Modern deep learning workloads in autonomous systems, robotics, and datacenter serving increasingly demand **spatial multi-tenancy** (running multiple models concurrently) alongside **multi-modal workload heterogeneity** (running CNN backbones, Transformer Self-Attention, and Depthwise convolutions simultaneously).

### The Fundamental Literature Gap
Prior deep learning accelerators force a mutually exclusive architectural compromise:
1. **Homogeneous Spatial Fission (e.g., Planaria, MICRO'20):** Dynamically partitions the physical systolic array into sub-arrays for concurrent multi-tenancy, but **locks all partitions to a single, rigid dataflow—predominantly Weight-Stationary (WS)**. When a partition executes a Transformer Self-Attention layer ($Q \cdot K^T$), it suffers severe energy and memory traffic overhead because WS is mathematically ill-suited for transient activation-activation multiplications.
2. **Single-Tenant Dataflow Switching (e.g., ReDas, IEEE TC'24):** Allows runtime switching across Weight-Stationary (WS), Output-Stationary (OS), and Input-Stationary (IS), but **operates exclusively on a single tenant across the entire physical array**. Multi-model workloads must queue serially, causing Head-of-Line (HoL) blocking and poor hardware utilization on small-to-medium models.

### Our Solution: Heterogeneous Fission (PolyFlow-NPU)
PolyFlow-NPU unifies both paradigms for the first time:
$$\textbf{PolyFlow-NPU} = \textbf{Concurrent Spatial Multi-Tenancy} + \textbf{Independent Per-Region Polymorphic Dataflow Selection}$$

Each dynamically partitioned region independently selects its mathematically optimal dataflow at runtime:
- **Region A:** Executes a CNN backbone (ResNet/ConvNeXt) in **Weight-Stationary (WS)** mode.
- **Region B:** Concurrently executes Transformer Self-Attention in **Output-Stationary (OS)** mode on the exact same clock cycles.
- **Hardware Isolation & Memory Safety:** Enforced via dynamic systolic boundary zeroing, an Event-Driven Phase-Pinned Arbiter (**EPPA**) that shifts idle bandwidth to streaming tenants, and a **4-cycle mandatory zeroing scrub** with decentralized single-writer ownership tokens (**OTP**).

---

## 2. The Three Architectural Exploration Models

To isolate, evaluate, and benchmark each contribution systematically, this repository provides three self-contained models:

| Model Folder | Architectural Configuration | Multi-Tenancy | Per-Region Dataflow | Key Workload Fit |
|---|---|:---:|:---:|---|
| [**`models/dataflow_switching/`**](file:///root/research/mt_npu/models/dataflow_switching) | **Configuration B**<br/>*(ReDas Baseline)* | Single Tenant Only | Global WS ⇄ OS ⇄ IS | Single-model sequential layer execution |
| [**`models/spatial_fission/`**](file:///root/research/mt_npu/models/spatial_fission) | **Configuration A**<br/>*(Planaria Baseline)* | Multi-Tenant (Region A + B) | Rigidly Locked to WS | Concurrent CNN workloads |
| [**`models/heterogeneous_fission/`**](file:///root/research/mt_npu/models/heterogeneous_fission) | **Configuration C**<br/>*(Novel Proposed Idea)* | **Multi-Tenant (Region A + B)** | **Independent Runtime WS / OS / IS** | **Simultaneous CNN (WS) + Transformer (OS) co-execution** |

---

## 3. Repository Directory Structure

```
mt_npu/
├── figures/                              # Publication-grade architectural diagrams
│   ├── fig0_comparison.dot (.png, .svg)  # Side-by-side taxonomy & comparative matrix
│   ├── figA_homo_fission.dot (.png, .svg)# Configuration A: Homogeneous Fission Pod
│   ├── figB_seq_switch.dot (.png, .svg)  # Configuration B: Sequential Dataflow Switching Pod
│   └── figC_hetero_fission.dot (.png, .svg)# Configuration C: Proposed Heterogeneous Fission Pod
│
├── models/                               # Self-contained architectural models
│   ├── dataflow_switching/               # [Model 1] Single-tenant runtime switching
│   │   ├── rtl/                          # Hardware RTL (dfs_pe, dfs_array, dfs_top)
│   │   ├── tb/                           # Standalone SystemVerilog testbench (dfs_top_tb.v)
│   │   ├── architecture.md               # Detailed microarchitecture specification
│   │   └── README.md                     # Build and execution guide
│   │
│   ├── spatial_fission/                  # [Model 2] Homogeneous spatial multi-tenancy
│   │   ├── rtl/                          # Hardware RTL (sfa_pe, sfa_array, sfa_fission_dec, sfa_eppa, etc.)
│   │   ├── tb/                           # Standalone SystemVerilog testbench (sfa_top_tb.v)
│   │   ├── architecture.md               # Detailed microarchitecture specification
│   │   └── README.md                     # Build and execution guide
│   │
│   └── heterogeneous_fission/            # [Model 3] Novel Heterogeneous Fission (PolyFlow-NPU)
│       ├── rtl/                          # Hardware RTL (hdf_pe, hdf_array_grid, hdf_fission_dec, etc.)
│       ├── tb/                           # Standalone SystemVerilog testbench (hdf_top_tb.v)
│       ├── architecture.md               # Detailed microarchitecture specification
│       └── README.md                     # Build and execution guide
│
├── scripts/
│   ├── render_figures.sh                 # Renders all .dot diagrams to PNG (160 dpi) and SVG
│   └── run_all_models.sh                 # Unified testbench runner for Verilator and Icarus Verilog
│
├── local/                                # Local working references & baseline specs (gitignored)
│   ├── architecture.md
│   ├── full_architecture.md
│   ├── dataflow_switching_baseline.md
│   ├── fission_baseline.md
│   └── evaluation_framework.md
│
├── .gitignore                            # Ignores build artifacts and local/ directory
└── README.md                             # Repository root documentation (this file)
```

---

## 4. Key Hardware Subsystems & Invariants

```
                               +------------------------------------+
                               | Multi-Tenant Host Tile Dispatcher  |
                               +------------------------------------+
                                                 |
                                                 v
                               +------------------------------------+
                               | Dynamic Fission Column Decoder     |
                               +------------------------------------+
                                       /                    \
                     (cfg_split_col)  /                      \  (dataflow_mode)
                                     v                        v
            +-------------------------------+  ||  +-------------------------------+
            |  Region A Sub-Array (Cols 0-1)|  ||  |  Region B Sub-Array (Cols 2-3)|
            |  Mode: Weight-Stationary (WS) |  ||  |  Mode: Output-Stationary (OS) |
            |  Workload: CNN Conv2D         |  ||  |  Workload: Self-Attention     |
            +-------------------------------+  ||  +-------------------------------+
                                               ||
                                    Dynamic Boundary Barrier
                                    (Active Zeroing Isolation)
                                               |
                          +--------------------+--------------------+
                          |  Shared Reconfigurable SRAM Substrate   |
                          |  • EPPA Arbiter: Dynamic Bandwidth Shift|
                          |  • OTP Token: Single-Writer Exclusion   |
                          |  • Bank Scrub: 4-Cycle Zeroing Security |
                          +-----------------------------------------+
```

1. **Heterogeneous PE (`hdf_pe.v`):** Unifies 3-way runtime operand multiplexing (WS/OS/IS) with an in-flight **lifetime countdown counter** (`lifetime_cnt`) that gracefully drains partial sums during partition re-sizing, and a **bank role stale flag** (`bank_role_stale`) protecting against stale memory reads.
2. **Dynamic Boundary Barrier (`hdf_array_grid.v`):** Slices the 2D mesh at `cfg_split_col`. Wires crossing the boundary are actively zeroed to guarantee **provable zero cross-talk** between tenants.
3. **Event-Driven Phase-Pinned Arbiter (EPPA, `eppa_arbiter.v`):** Reallocates memory bandwidth upon phase transitions (`BURST`, `STREAM`, `IDLE`, `RECONFIG`). When Region A enters steady-state compute, its idle bandwidth automatically shifts to Region B's streaming query/key buffers.
4. **Decentralized Single-Writer Tokens (OTP, `otp_token_fsm.v`) & 4-Cycle Scrub (`pod_bank_scrub.v`):** Epoch-rotating priority guarantees starvation-free memory access, while a mandatory 4-cycle hardware zeroing scrub wipes residual tenant weights before memory release, eliminating side-channel data-retention attacks.

---

## 5. Quickstart & Simulation Guide

### Prerequisites
* **Verilator 5.020+** (recommended for high-speed simulation with native timing)
* **Icarus Verilog 12+** (`iverilog` / `vvp` dual compatibility)
* **Graphviz** (`dot` for rendering architecture figures)

### Running All Models with a Single Command
To execute the automated simulation testsuite across all three architectural models:

```bash
# Run all 3 models with Verilator (default)
./scripts/run_all_models.sh verilator

# Or run all 3 models with Icarus Verilog
./scripts/run_all_models.sh iverilog
```

### Running Individual Models
```bash
# Model 1: Dataflow Switching
cd models/dataflow_switching
verilator --binary --timing -Wall rtl/*.v tb/dfs_top_tb.v --top-module dfs_top_tb -o Vdfs_top_tb && ./obj_dir/Vdfs_top_tb

# Model 2: Spatial Fission
cd models/spatial_fission
verilator --binary --timing -Wall rtl/*.v tb/sfa_top_tb.v --top-module sfa_top_tb -o Vsfa_top_tb && ./obj_dir/Vsfa_top_tb

# Model 3: Heterogeneous Fission (PolyFlow-NPU)
cd models/heterogeneous_fission
verilator --binary --timing -Wall rtl/*.v tb/hdf_top_tb.v --top-module hdf_top_tb -o Vhdf_top_tb && ./obj_dir/Vhdf_top_tb
```

### Rendering Architecture Figures
```bash
./scripts/render_figures.sh
```

---

## 6. Verification Status

All RTL modules and testbenches are validated with **0 errors and 0 warnings** under `verilator --lint-only -Wall`:

```
==================================================================
 [PolyFlow-NPU] Complete Architectural Exploration Testsuite Results
==================================================================
>>> [MODEL 1] Dataflow Switching    : PASS (WS: 60, OS: 55, IS: 72)
>>> [MODEL 2] Spatial Fission       : PASS (Reg A: 60, Reg B: 56, Zero Leakage)
>>> [MODEL 3] Heterogeneous Fission : PASS (Reg A WS: 60, Reg B OS: 40, Concurrent)
==================================================================
 [SUCCESS] ALL THREE MODELS PASSED SIMULATION AND LINT VERIFICATION!
==================================================================
```
