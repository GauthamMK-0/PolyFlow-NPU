# Model 1: Single-Tenant Dataflow Switching Architecture (Pipelined)

## 1. Overview
This directory contains the standalone **Dataflow Switching Model** (corresponding to **Configuration B** in `evaluation_framework.md` / ReDas-style architecture).

### Architectural Characteristics
* **Single Tenant:** A single workload occupies the entire physical PE array ($M \times N$).
* **Runtime Dataflow Reconfiguration:** Allows per-tile switching across three core dataflows:
  1. `2'b00` — **Weight-Stationary (WS):** Best for Convolution and Fully-Connected layers with high filter reuse. Weights remain stationary in PEs; inputs stream from North, partial sums accumulate vertically.
  2. `2'b01` — **Output-Stationary (OS):** Optimal for Self-Attention matrix multiplications ($Q \cdot K^T$ and $S \cdot V$) where both inputs are transient activations. Queries stream from North, Keys stream from West; partial sums remain stationary and accumulate locally.
  3. `2'b10` — **Input-Stationary (IS):** Optimal for Depthwise-Separable convolutions. Activations remain stationary; weights stream from West, partial sums accumulate vertically.
* **Two-Stage Pipelined MAC:** Eliminates recursive accumulation delay bottlenecks using a registered product stage and redundant carry-save accumulator (CSA) loops.
* **No Spatial Fission:** Demonstrates dataflow flexibility in isolation without concurrent multi-tenancy or array partitioning.

---

## 2. Directory Structure & Partitioned Scaling Layout
```
models/pipelined/dataflow_switching/
├── rtl/
│   ├── dfs_pe.sv              # Heterogeneous Processing Element with WS/OS/IS multiplexing & CSA
│   ├── dfs_array.sv           # Parameterized 2D Systolic Array Grid
│   ├── dfs_top.sv             # Top-level array controller (parameterized default 4x4)
│   ├── dfs_top_8x8.sv         # Dedicated 8x8 scaled pod wrapper
│   └── dfs_top_16x16.sv       # Dedicated 16x16 full pod wrapper
├── tb/
│   ├── dfs_top_tb.sv          # 4x4 baseline testbench validating sequential tile switching
│   ├── dfs_top_8x8_tb.sv      # 8x8 scaled pod testbench (64 PEs)
│   └── dfs_top_16x16_tb.sv    # 16x16 full pod testbench (256 PEs)
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
| **4x4** (Baseline) | 16 PEs | 1,504 flops | 6.4 GOPS | `tb/dfs_top_tb.sv` |
| **8x8** (Scaled Pod) | 64 PEs | 6,016 flops | 25.6 GOPS | `tb/dfs_top_8x8_tb.sv` |
| **16x16** (Full Pod) | 256 PEs | 24,064 flops | 102.4 GOPS | `tb/dfs_top_16x16_tb.sv` |

---

## 4. Verification & Simulation

### Testbench Architecture
The testbenches validate seamless runtime dataflow switching across all three dataflows:
1. **Weight-Stationary (WS) Mode:** Preloads stationary weights from West port and streams inputs from North port; verifies accumulated dot products across all PEs.
2. **Output-Stationary (OS) Mode:** Streams queries from North and keys from West simultaneously; accumulates results locally in redundant carry-save accumulators.
3. **Input-Stationary (IS) Mode:** Preloads stationary activations from North port and streams weights from West; verifies accumulated dot products.

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

Model 1 is configured for multi-scale logic synthesis mapped to standard cells (`slow.lib`) using Cadence Genus:

```bash
make synth-4x4      # Synthesize 4x4 netlist and reports (reports/4x4/, netlist/4x4/)
make synth-8x8      # Synthesize 8x8 netlist and reports (reports/8x8/, netlist/8x8/)
make synth-16x16    # Synthesize 16x16 netlist and reports (reports/16x16/, netlist/16x16/)
make synth-scaling  # Synthesize all scales sequentially
```

### Synthesis Specifications & Optimizations
- **Target Frequency**: **200 MHz** ($T_{\text{clk}} = 5.000\text{ ns}$)
- **I/O Delay Budget**: $0.500\text{ ns}$ (10% of clock period)
- **Clock Uncertainty**: $0.050\text{ ns}$ (setup margin)
- **Timing Model**: Pure synchronous single-cycle STA across all paths
- **Timing Slack**: Robust positive setup slack ($\ge +1.5\text{ ns}$) across all paths

---

## 6. Physical Design & Implementation (Cadence Innovus)

Model 1 includes a complete physical design flow (Floorplanning, Power Grid, Placement, CTS, Detailed Routing, Signoff):

```bash
make pnr-place-4x4      # Complete PnR flow for 4x4 (outputs in outputs/4x4/, db/4x4/)
make pnr-place-8x8      # Complete PnR flow for 8x8 (outputs in outputs/8x8/, db/8x8/)
make pnr-place-16x16    # Complete PnR flow for 16x16 (outputs in outputs/16x16/, db/16x16/)
make pnr-place-scaling  # PnR across all scales
```

- **Standard Cell Library**: 90nm bulk CMOS (`gsclib090_translated.lef`)
- **Clock Tree Synthesis**: CCOpt clock tree engine with non-default NDR rules (`2w2s`)
- **Deliverables**: Placed & routed DEF (`outputs/${SCALE}/dfs_top_postroute.def`), signoff netlist, and SDF timing files.
