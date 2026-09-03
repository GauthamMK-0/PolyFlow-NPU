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
models/spatial_fission/
├── rtl/
│   ├── sfa_pe.v              # Processing element pinned to Weight-Stationary
│   ├── sfa_fission_decoder.v # Dynamic column split decoder
│   ├── sfa_array.v           # 2D systolic array with hardware boundary isolation
│   ├── sfa_otp_fsm.v         # Single-writer ownership token FSM
│   ├── sfa_bank_scrub.v      # 4-cycle zeroing scrub controller
│   ├── sfa_eppa.v            # Event-driven phase-pinned bandwidth arbiter
│   └── sfa_top.v             # Top-level multi-tenant pod
├── tb/
│   └── sfa_top_tb.v          # Standalone SystemVerilog testbench
└── README.md
```

---

## Verification & Simulation

### Using Verilator
```bash
cd models/spatial_fission
verilator --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
    rtl/sfa_pe.v rtl/sfa_fission_decoder.v rtl/sfa_array.v \
    rtl/sfa_otp_fsm.v rtl/sfa_bank_scrub.v rtl/sfa_eppa.v rtl/sfa_top.v \
    tb/sfa_top_tb.v --top-module sfa_top_tb -o Vsfa_top_tb
./obj_dir/Vsfa_top_tb
```

### Using Icarus Verilog (Alternative)
```bash
cd models/spatial_fission
iverilog -g2012 -o tb/sfa_top_tb.vvp rtl/*.v tb/sfa_top_tb.v
vvp tb/sfa_top_tb.vvp
```
