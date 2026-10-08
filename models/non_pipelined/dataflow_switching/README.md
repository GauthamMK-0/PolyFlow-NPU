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
models/non_pipelined/dataflow_switching/
├── rtl/
│   ├── dfs_pe.sv      # Heterogeneous Processing Element with WS/OS/IS multiplexing
│   ├── dfs_array.sv   # 2D Systolic Array Grid
│   └── dfs_top.sv     # Top-level array controller
├── tb/
│   └── dfs_top_tb.sv  # SystemVerilog testbench validating sequential tile switching
├── dfs_top.sdc        # SDC timing constraints (250 MHz / 4.000 ns clock target)
├── synth_dfs.tcl      # Cadence Genus synthesis execution script
├── Makefile           # Cadence Xcelium & Genus automation
└── README.md
```

---

## Verification & Simulation

### Test Suite & Verification Matrix
The test harness (`tb/dfs_top_tb.sv`) implements a modular hybrid verification architecture:
- `test_ws_mode.svh`: Weight-Stationary (WS) execution with stationary weight preload and combinational product output.
- `test_os_mode.svh`: Output-Stationary (OS) execution with dual streaming operands (Q from North, K from West).
- `test_is_mode.svh`: Input-Stationary (IS) execution with stationary input preload and streaming weights.
- `test_corner_compute_gating.svh`: Compute enable gating and product zero-clamping verification.
- `test_random_stimulus.svh`: Multi-cycle constrained-random stimulus across all 3 dataflows self-checked against a golden model.
- `dfs_coverage_monitor.svh`: Dual-compatible functional coverage engine with IEEE 1800 covergroups for Cadence IMC and active bin tracker (**15 / 15 bins = 100.0% coverage**).

### Using Cadence Xcelium (xrun)
```bash
cd models/non_pipelined/dataflow_switching
make run           # Headless batch mode (default)
make gui           # Interactive GUI mode with SimVision
make run TEST=ws   # Run specific testcase (e.g. ws, os, is, gating, random)
make clean         # Clean output/ sandbox and log files
```

### Using Verilator
```bash
cd models/non_pipelined/dataflow_switching
verilator -j $(nproc) --binary --timing -Wall -Itb -Itb/tests \
    rtl/*.sv tb/dfs_top_tb.sv --top-module dfs_top_tb -o Vdfs_top_tb
./obj_dir/Vdfs_top_tb +TEST=ALL
```

### Using Icarus Verilog (Alternative)
```bash
cd models/non_pipelined/dataflow_switching
iverilog -g2012 -I tb -I tb/tests -o tb/dfs_top_tb.vvp rtl/*.sv tb/dfs_top_tb.sv
vvp tb/dfs_top_tb.vvp +TEST=ALL
```

---

## ASIC Logic Synthesis & Timing Closure (Cadence Genus @ 250 MHz)

Model 1 baseline is pre-configured for logic synthesis mapped to standard cells (`slow.lib`) using Cadence Genus:

```bash
cd models/non_pipelined/dataflow_switching
make synth            # Runs genus with synth_dfs.tcl and dfs_top.sdc
```

### Synthesis Specifications & Optimizations
- **Target Frequency**: **250 MHz** ($T_{\text{clk}} = 4.000\text{ ns}$)
- **I/O Delay Budget**: $0.400\text{ ns}$ (10% of clock period)
- **Clock Uncertainty**: $0.150\text{ ns}$ (setup margin)
- **Operand MUX Pruning**: Direct wire on `mul_b`, 2:1 MUX on `mul_a`, eliminating 4:1 multiplexer tree delay
- **Hierarchy Optimization**: Auto-ungroups and flattens array partitions to eliminate module boundary pins (`set_db auto_ungroup both`, `catch { ungroup -all -flatten }`)
- **Datapath**: Decoupled single-cycle multiplier tree with sparsity clock gating, achieving positive timing slack ($\ge +2.5\text{ ns}$)

