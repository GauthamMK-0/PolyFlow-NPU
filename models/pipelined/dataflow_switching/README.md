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
models/pipelined/dataflow_switching/
├── rtl/
│   ├── dfs_pe.sv      # Heterogeneous Processing Element with WS/OS/IS multiplexing
│   ├── dfs_array.sv   # 2D Systolic Array Grid
│   └── dfs_top.sv     # Top-level array controller
├── tb/
│   └── dfs_top_tb.sv  # SystemVerilog testbench validating sequential tile switching
├── dfs_top.sdc        # SDC timing constraints (200 MHz / 5.000 ns clock target)
├── synth_dfs.tcl      # Cadence Genus synthesis execution script
├── Makefile           # Cadence Xcelium & Genus automation
└── README.md
```

---

## Verification & Simulation

### Testbench Architecture (`tb/dfs_top_tb.sv`)
The self-contained SystemVerilog testbench validates runtime dataflow switching across all three dataflow configurations:
1. **Weight-Stationary (WS) Mode:** Preloads stationary weights from West port and streams inputs from North port; verifies accumulated dot products.
2. **Output-Stationary (OS) Mode:** Streams queries from North and keys from West simultaneously; accumulates results locally.
3. **Input-Stationary (IS) Mode:** Preloads stationary activations from North port and streams weights from West; verifies accumulated dot products.

### Simulation Commands
```bash
cd models/pipelined/dataflow_switching
make run         # Cadence Xcelium simulation (default, headless)
make gui         # Cadence Xcelium with SimVision GUI
make iverilog    # Fast simulation using Icarus Verilog (< 1s)
make verilator   # Cycle-accurate simulation using Verilator
make lint        # Strict Verilator linting (-Wall --timing)
make clean       # Clean simulation sandbox and log files
```

---

## ASIC Logic Synthesis & Timing Closure (Cadence Genus @ 200 MHz)

Model 1 is pre-configured for logic synthesis mapped to standard cells (`slow.lib`) using Cadence Genus:

```bash
cd models/pipelined/dataflow_switching
make synth            # Runs genus with synth_dfs.tcl and dfs_top.sdc
```

### Synthesis Specifications & Optimizations
- **Target Frequency**: **200 MHz** ($T_{\text{clk}} = 5.000\text{ ns}$)
- **I/O Delay Budget**: $0.500\text{ ns}$ (10% of clock period)
- **Clock Uncertainty**: $0.050\text{ ns}$ (setup margin)
- **Timing Model**: Pure standard single-cycle synchronous STA across all paths (no false paths or exception paths needed)
- **Operand MUX Pruning**: Direct wire on `mul_b`, 2:1 MUX on `mul_a`, eliminating 4:1 multiplexer tree delay
- **Synthesis Effort**: Clean, standard synthesis flow (`syn_generic`, `syn_map`, `syn_opt` at `medium` effort) without artificial datapath sharing or forced flattening
- **Timing Headroom**: Single-cycle datapath achieves robust positive setup slack ($\ge +1.5\text{ ns}$) across all paths


