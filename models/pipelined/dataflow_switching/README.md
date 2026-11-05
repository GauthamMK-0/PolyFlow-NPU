# Model 1: Single-Tenant Dataflow Switching Architecture (Pipelined)

## 1. Overview
This directory contains the standalone **Dataflow Switching Model** (corresponding to **Configuration B** in `evaluation_framework.md` / ReDas-style architecture).

### Architectural Characteristics
* **Single Tenant:** A single workload occupies the entire physical PE array ($M \times N$).
* **Runtime Dataflow Reconfiguration:** Allows per-tile switching across three core dataflows:
  1. `2'b00` — **Weight-Stationary (WS):** Best for Convolution and Fully-Connected layers with high filter reuse. Weights remain stationary in PEs; inputs stream from West, partial sums accumulate vertically South across 32-bit ports (`din_n` $\to$ `dout_s`).
  2. `2'b01` — **Output-Stationary (OS):** Optimal for Self-Attention matrix multiplications ($Q \cdot K^T$ and $S \cdot V$) where both inputs are transient activations. Queries stream from North, Keys stream from West; partial sums remain stationary and accumulate locally.
  3. `2'b10` — **Input-Stationary (IS):** Optimal for Depthwise-Separable convolutions. Activations remain stationary; weights stream from West, partial sums accumulate vertically South.
* **32-Bit Vertical Partial-Sum Mesh & Registered Systolic Forwarding:**
  - Upgraded vertical channels to 32 bits (`ACC_W = 32`) to eliminate accumulation overflow.
  - Every inter-PE hop is registered (`1 hop/cycle`), preventing combinational loop formation.
* **Two-Stage Pipelined MAC with 3:2 Carry-Save Accumulator (CSA):**
  - Eliminates recursive accumulation delay bottlenecks using a registered product stage (`product_reg`) and redundant carry-save accumulator (CSA) loops (`acc_sum`, `acc_carry`).
* **Pipeline Flush Rule on Reconfiguration:**
  - Requires `NUM_ROWS + NUM_COLS + 2` cycles of zero inputs before dataflow reconfiguration or accumulator clearing to purge in-flight operands from inter-PE forwarding registers.
* **No Spatial Fission:** Demonstrates dataflow flexibility in isolation without concurrent multi-tenancy or array partitioning.

---

## 2. Directory Structure & Partitioned Scaling Layout
```
models/pipelined/dataflow_switching/
├── rtl/
│   ├── dfs_pe.sv              # Heterogeneous Processing Element with WS/OS/IS multiplexing & CSA
│   ├── dfs_array.sv           # Parameterized 2D Systolic Array Grid (registered hops)
│   ├── dfs_top.sv             # Top-level array controller (parameterized default 4x4)
│   ├── dfs_top_8x8.sv         # Dedicated 8x8 scaled pod wrapper
│   └── dfs_top_16x16.sv       # Dedicated 16x16 full pod wrapper
├── tb/
│   ├── dfs_top_tb.sv          # 4x4 baseline testbench (exhaustive 16-PE assertions across WS/OS/IS)
│   ├── dfs_top_8x8_tb.sv      # 8x8 scaled pod testbench (exhaustive 64-PE assertions across WS/OS/IS)
│   └── dfs_top_16x16_tb.sv    # 16x16 full pod testbench (exhaustive 256-PE assertions across WS/OS/IS)
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

## 3. Scalable Array Configurations (4x4, 8x8, 16x16)

Model 1 supports parameterized array dimensions configured via `SCALE`:

| Dimension | Processing Elements | Flip-Flop Count | INT8 Throughput (@ 200 MHz) | Primary Testbench |
| :---: | :---: | :---: | :---: | :--- |
| **4x4** (Baseline) | 16 PEs | 1,504 flops | 6.40 GOPS | `tb/dfs_top_tb.sv` |
| **8x8** (Scaled Pod) | 64 PEs | 6,016 flops | 25.60 GOPS | `tb/dfs_top_8x8_tb.sv` |
| **16x16** (Full Pod) | 256 PEs | 24,064 flops | 102.40 GOPS | `tb/dfs_top_16x16_tb.sv` |

---

## 4. Verification & Simulation

### Testbench Architecture
The testbenches validate seamless runtime dataflow switching across all three dataflows with **exhaustive grid assertion coverage**:
1. **Weight-Stationary (WS) Mode:** Preloads unique stationary weights via West-to-East shift and streams inputs from the West boundary; verifies vertical partial-sum accumulation across **100% of all PEs**.
2. **Output-Stationary (OS) Mode:** Streams queries from North and keys from West with systolic diamond skewing; verifies localized accumulation in parallel CSA registers across **100% of all PEs**.
3. **Input-Stationary (IS) Mode:** Preloads stationary activations from North and streams weights from West; verifies accumulation across **100% of all PEs**.

### Simulation Commands
```bash
# Fast Icarus Verilog simulation per scale:
make test-4x4       # Run 4x4 baseline simulation (output in output/4x4/)
make test-8x8       # Run 8x8 scaled pod simulation (output in output/8x8/)
make test-16x16     # Run 16x16 full pod simulation (output in output/16x16/)
make test-scaling   # Run complete scaling regression across all sizes

# Cadence Xcelium simulation:
make run SCALE=4x4  # Headless batch simulation
make run SCALE=8x8  # 8x8 scaled pod simulation
make gui SCALE=4x4  # Interactive SimVision GUI mode

# Verilator cycle-accurate simulation:
make verilator-4x4
make verilator-8x8
make verilator-16x16

# Linting & Cleanup:
make lint           # Strict Verilator linting (-Wall --timing)
make clean          # Clean simulation sandboxes without deleting tracked reports
```

---

## 5. ASIC Logic Synthesis (Cadence Genus @ 200 MHz)

```bash
make synth-4x4      # Synthesize 4x4 netlist and reports (reports/4x4/, netlist/4x4/)
make synth-8x8      # Synthesize 8x8 netlist and reports (reports/8x8/, netlist/8x8/)
make synth-16x16    # Synthesize 16x16 netlist and reports (reports/16x16/, netlist/16x16/)
make synth-scaling  # Synthesize all scales sequentially
```

---

## 6. Physical Design & Implementation (Cadence Innovus)

```bash
make pnr-place-4x4      # Complete PnR flow for 4x4 (outputs in outputs/4x4/, db/4x4/)
make pnr-place-8x8      # Complete PnR flow for 8x8 (outputs in outputs/8x8/, db/8x8/)
make pnr-place-16x16    # Complete PnR flow for 16x16 (outputs in outputs/16x16/, db/16x16/)
make pnr-place-scaling  # PnR across all scales
```
