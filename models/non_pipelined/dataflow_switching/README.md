# Model 1: Single-Tenant Dataflow Switching Architecture (Non-Pipelined Baseline)

## 1. Overview
This directory contains the **Non-Pipelined Combinational Baseline** of the Dataflow Switching Model (corresponding to **Configuration B** in `evaluation_framework.md` / ReDas-style architecture).

### Key Architectural Characteristics
* **Single Tenant:** A single workload occupies the entire physical PE array ($M \times N$).
* **Runtime Dataflow Reconfiguration:** Allows per-tile switching across three core dataflows:
  1. `2'b00` — **Weight-Stationary (WS):** Best for Convolution and Fully-Connected layers with high filter reuse. Weights remain stationary in PEs; inputs stream from West, partial sums accumulate vertically South across 32-bit ports (`din_n` $\to$ `dout_s`).
  2. `2'b01` — **Output-Stationary (OS):** Optimal for Self-Attention matrix multiplications ($Q \cdot K^T$ and $S \cdot V$) where both inputs are transient activations. Queries stream from North, Keys stream from West; partial sums remain stationary and accumulate locally.
  3. `2'b10` — **Input-Stationary (IS):** Optimal for Depthwise-Separable convolutions. Activations remain stationary; weights stream from West, partial sums accumulate vertically South.
* **32-Bit Vertical Partial-Sum Mesh:** Vertical ports (`din_n` / `dout_s`) are widened to 32 bits (`ACC_W = 32`), providing bit-for-bit mathematical parity with the pipelined model without accumulator overflow.
* **Single-Cycle Combinational MAC Baseline:** Implements direct multiplication and recursive accumulation in a single clock cycle, serving as the timing, power, and area baseline to quantify the performance and clock frequency gains offered by the pipelined carry-save accumulator (CSA) design.
* **No Spatial Fission:** Demonstrates dataflow flexibility in isolation without concurrent multi-tenancy or array partitioning.

---

## 2. Directory Structure & Layout
```
models/non_pipelined/dataflow_switching/
├── rtl/
│   ├── dfs_pe.sv              # Heterogeneous PE with single-cycle combinational MAC (32-bit psum)
│   ├── dfs_array.sv           # 2D Systolic Array Grid
│   └── dfs_top.sv             # Top-level array controller (4x4 baseline)
├── tb/
│   └── dfs_top_tb.sv          # Standalone SystemVerilog testbench (exhaustive 16 PEs across WS/OS/IS)
├── reports/                   # Cadence Genus & Innovus synthesis/PnR reports
│   ├── 4x4/                   # 4x4 baseline reports (timing, area, power, qor, gates)
│   ├── 8x8/                   # 8x8 scaled pod reports
│   ├── 16x16/                 # 16x16 full pod reports
│   └── cts/                   # Clock Tree Synthesis reports
├── netlist/                   # Gate-level netlists & timing models
│   ├── 4x4/                   # dfs_top_netlist.v, .sdc, .sdf for 4x4
│   ├── 8x8/                   # Gate-level netlist for 8x8
│   └── 16x16/                 # Gate-level netlist for 16x16
├── output/                    # Simulation executables & waveforms
│   ├── 4x4/                   # 4x4 simulation outputs (.vvp, .vcd)
│   ├── 8x8/                   # 8x8 simulation outputs
│   └── 16x16/                 # 16x16 simulation outputs
├── outputs/                   # Cadence Innovus physical design signoff deliverables
│   ├── 4x4/                   # Post-route DEF, netlist, and SDF (4x4)
│   ├── 8x8/                   # Post-route deliverables (8x8)
│   └── 16x16/                 # Post-route deliverables (16x16)
├── db/                        # Cadence Innovus database checkpoints (.enc)
│   ├── 4x4/                   # Checkpoints from init to postroute (4x4)
│   ├── 8x8/                   # Checkpoints for 8x8
│   └── 16x16/                 # Checkpoints for 16x16
├── dfs_top.sdc                # SDC timing constraints (200 MHz / 5.000 ns clock target)
├── synth_dfs.tcl              # Multi-scale Cadence Genus synthesis script
├── pnr_place_dfs.tcl          # Multi-scale Cadence Innovus physical design script
├── Makefile                   # Automation Makefile for simulation, synthesis, and PnR
└── README.md
```

---

## 3. Verification & Simulation

### Testbench Architecture
The standalone testbench (`tb/dfs_top_tb.sv`) validates seamless runtime dataflow switching across all three dataflows with **exhaustive 16-PE assertion coverage**:
1. **Weight-Stationary (WS) Mode:** Preloads stationary weights via West-to-East shift and streams inputs from the West boundary; verifies vertical partial-sum accumulation across **100% of all 16 PEs**.
2. **Output-Stationary (OS) Mode:** Streams queries from North (`din_n`, 32-bit) and keys from West (`din_w`, 8-bit) across multiple cycles; verifies localized accumulation in accumulator registers across **100% of all 16 PEs**.
3. **Input-Stationary (IS) Mode:** Preloads stationary activations from North and streams weights from West; verifies combinational accumulation across **100% of all 16 PEs**.

### Simulation Commands
```bash
# Fast Icarus Verilog simulation:
make test-4x4       # Run 4x4 baseline simulation verifying all 16 PEs (output in output/4x4/)
make iverilog       # Alias to test-4x4

# Cadence Xcelium simulation:
make run SCALE=4x4  # Headless batch simulation
make gui SCALE=4x4  # Interactive SimVision GUI mode

# Verilator cycle-accurate simulation:
make verilator-4x4

# Linting & Cleanup:
make lint           # Strict Verilator linting (-Wall --timing)
make clean          # Clean temporary sandbox files without deleting tracked reports
```

---

## 4. ASIC Logic Synthesis (Cadence Genus @ 200 MHz)

```bash
make synth-4x4      # Synthesize 4x4 netlist and reports (reports/4x4/, netlist/4x4/)
```

---

## 5. Physical Design & Implementation (Cadence Innovus)

```bash
make pnr-place-4x4  # Complete PnR flow for 4x4 (outputs in outputs/4x4/, db/4x4/)
```
