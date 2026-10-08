# Model 2: Homogeneous Spatial Fission Architecture

## Overview
This directory contains the standalone **Spatial Fission Model** (corresponding to **Configuration A** in `evaluation_framework.md` / Planaria-style architecture).

### Architectural Characteristics
* **Spatial Multi-Tenancy (Fission):** A single physical PE array is dynamically partitioned into two independently operating regions (Region A and Region B) via dispatch-time column splitting (`cfg_split_col`).
* **Hardware Boundary Isolation:** Inter-region systolic mesh lines are dynamically forced to zero at column boundaries, preventing cross-tenant operand bleeding.
* **Homogeneous Dataflow Constraint:** All regions are constrained/pinned to the same global dataflow (Weight-Stationary). This captures the fundamental limitation of prior spatial multi-tenant accelerators.
* **Shared Memory Substrate:** Memory banks are arbitrated via:
  - Single-writer ownership token protocol (OTP) with rotating epoch priority.
  - Mandatory 4-cycle zeroing scrub controller before bank role migration.
  - Event-driven phase-pinned memory bandwidth arbiter (EPPA).

---

## Directory Structure
```
models/pipelined/spatial_fission/
├── rtl/
│   ├── sfa_pe.sv              # Processing element pinned to Weight-Stationary
│   ├── sfa_fission_decoder.sv # Dynamic column split decoder
│   ├── sfa_array.sv           # 2D systolic array with hardware boundary isolation
│   ├── sfa_otp_fsm.sv         # Single-writer ownership token FSM
│   ├── sfa_bank_scrub.sv      # 4-cycle zeroing scrub controller
│   ├── sfa_eppa.sv            # Event-driven phase-pinned bandwidth arbiter
│   └── sfa_top.sv             # Top-level multi-tenant pod
├── tb/
│   └── sfa_top_tb.sv          # Standalone SystemVerilog testbench
├── sfa_top.sdc                # SDC timing constraints (250 MHz / 4.000 ns clock target)
├── synth_sfa.tcl              # Cadence Genus synthesis execution script
├── Makefile                   # Cadence Xcelium & Genus automation
└── README.md
```

---

## Verification & Simulation

### Test Suite & Verification Matrix
The test harness (`tb/sfa_top_tb.sv`) implements a modular hybrid verification architecture:
- `test_split_partition.svh`: Dynamic dispatch-time column partitioning (Cols 0-1: Reg A, Cols 2-3: Reg B).
- `test_concurrent_ws.svh`: Multi-tenant concurrent execution with boundary electrical isolation.
- `test_eppa_phase_arb.svh`: EPPA memory bandwidth allocation across BURST, STREAM, IDLE, and RECONFIG phases with urgency flags.
- `test_mem_scrub.svh`: Memory bank migration with mandatory 4-cycle hardware zeroing scrub.
- `test_corner_bank_contention.svh`: Concurrent multi-tenant memory bank contention with mutual exclusion and starvation avoidance.
- `test_corner_reconfig_split.svh`: Dynamic online array fission across boundary columns 0, 1, 2, 3, 4.
- `test_corner_compute_gating.svh`: Per-region compute enable gating and accumulator freezing.
- `test_random_stimulus.svh`: Constrained-random stimulus with automated self-checking against a golden mathematical model.
- `sfa_coverage_monitor.svh`: Dual-compatible functional coverage engine with IEEE 1800 covergroups for Cadence IMC and active bin tracker (**19 / 19 bins = 100.0% coverage**).

### Using Cadence Xcelium (xrun)
```bash
cd models/pipelined/spatial_fission
make run              # Headless batch mode (default)
make gui              # Interactive GUI mode with SimVision
make run TEST=concurrent # Run specific testcase (e.g. contention, reconfig, gating, random)
make clean            # Clean output/ sandbox and log files
```

### Using Verilator
```bash
cd models/pipelined/spatial_fission
verilator -j $(nproc) --binary --timing -Wall -Itb -Itb/tests \
    rtl/*.sv tb/sfa_top_tb.sv --top-module sfa_top_tb -o Vsfa_top_tb
./obj_dir/Vsfa_top_tb +TEST=ALL
```

### Using Icarus Verilog (Alternative)
```bash
cd models/pipelined/spatial_fission
iverilog -g2012 -I tb -I tb/tests -o tb/sfa_top_tb.vvp rtl/*.sv tb/sfa_top_tb.sv
vvp tb/sfa_top_tb.vvp +TEST=ALL
```

---

## ASIC Logic Synthesis & Timing Closure (Cadence Genus @ 250 MHz)

Model 2 is pre-configured for logic synthesis mapped to standard cells (`slow.lib`) using Cadence Genus:

```bash
cd models/pipelined/spatial_fission
make synth            # Runs genus with synth_sfa.tcl and sfa_top.sdc
```

### Synthesis Specifications & Optimizations
- **Target Frequency**: **250 MHz** ($T_{\text{clk}} = 4.000\text{ ns}$)
- **I/O Delay Budget**: $0.400\text{ ns}$ (10% of clock period)
- **Clock Uncertainty**: $0.150\text{ ns}$ (setup margin)
- **Multicycle Paths (MCP)**: Applied to `region_id_mask` registers (`set_multicycle_path 2 -setup -from [get_cells -hier *region_id_mask*]`)
- **Boundary Optimization**: Pre-decoded boundary column flags (`is_boundary_col`) eliminate row-level boundary mux delays
- **Hierarchy Optimization**: Auto-ungroups and flattens array partitions to eliminate module boundary pins (`set_db auto_ungroup both`, `catch { ungroup -all -flatten }`)
- **Datapath**: Decoupled single-cycle multiplier tree with sparsity clock gating, achieving positive timing slack ($\ge +2.5\text{ ns}$)

