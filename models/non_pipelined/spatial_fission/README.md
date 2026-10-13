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
models/non_pipelined/spatial_fission/
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
├── sfa_top.sdc                # SDC timing constraints (200 MHz / 5.000 ns clock target)
├── synth_sfa.tcl              # Cadence Genus synthesis execution script
├── Makefile                   # Cadence Xcelium & Genus automation
└── README.md
```

---

## Verification & Simulation

### Testbench Architecture (`tb/sfa_top_tb.sv`)
The self-contained SystemVerilog testbench validates the core architectural features:
1. **Dynamic Column Partitioning:** Configures `cfg_split_col = 2` and verifies `region_id_mask = 1100`.
2. **Concurrent Execution:** Executes Region A and Region B concurrently (both in Weight-Stationary mode) with zero cross-talk across the partition boundary.
3. **EPPA Memory Bandwidth Arbitration:** Validates dynamic bandwidth allocation across differing tenant memory phases.
4. **Shared Memory Scrubbing:** Validates the 4-cycle hardware zeroing scrub sequence and `bank_role_clear` handshake.

### Simulation Commands
```bash
cd models/non_pipelined/spatial_fission
make run         # Cadence Xcelium simulation (default, headless)
make gui         # Cadence Xcelium with SimVision GUI
make iverilog    # Fast simulation using Icarus Verilog (< 1s)
make verilator   # Cycle-accurate simulation using Verilator
make lint        # Strict Verilator linting (-Wall --timing)
make clean       # Clean simulation sandbox and log files
```

---

## ASIC Logic Synthesis & Timing Closure (Cadence Genus @ 200 MHz)

Model 2 baseline is pre-configured for logic synthesis mapped to standard cells (`slow.lib`) using Cadence Genus:

```bash
cd models/non_pipelined/spatial_fission
make synth            # Runs genus with synth_sfa.tcl and sfa_top.sdc
```

### Synthesis Specifications & Optimizations
- **Target Frequency**: **200 MHz** ($T_{\text{clk}} = 5.000\text{ ns}$)
- **I/O Delay Budget**: $0.500\text{ ns}$ (10% of clock period)
- **Clock Uncertainty**: $0.050\text{ ns}$ (setup margin)
- **Timing Model**: Pure standard single-cycle synchronous STA across all paths (no multicycle paths or false path exceptions needed)
- **Boundary Optimization**: Pre-decoded boundary column flags (`is_boundary_col`) eliminate row-level boundary mux delays
- **Synthesis Effort**: Clean, standard synthesis flow (`syn_generic`, `syn_map`, `syn_opt` at `medium` effort) without artificial datapath sharing or forced flattening
- **Timing Headroom**: Single-cycle datapath achieves robust positive setup slack ($\ge +1.5\text{ ns}$) across all register-to-register and I/O paths


