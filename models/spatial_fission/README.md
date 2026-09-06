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
│   ├── sfa_pe.sv              # Processing element pinned to Weight-Stationary
│   ├── sfa_fission_decoder.sv # Dynamic column split decoder
│   ├── sfa_array.sv           # 2D systolic array with hardware boundary isolation
│   ├── sfa_otp_fsm.sv         # Single-writer ownership token FSM
│   ├── sfa_bank_scrub.sv      # 4-cycle zeroing scrub controller
│   ├── sfa_eppa.sv            # Event-driven phase-pinned bandwidth arbiter
│   └── sfa_top.sv             # Top-level multi-tenant pod
├── tb/
│   └── sfa_top_tb.sv          # Standalone SystemVerilog testbench
└── README.md
```

---

## Verification & Simulation

### Using Verilator
```bash
cd models/spatial_fission
verilator --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
    rtl/sfa_pe.sv rtl/sfa_fission_decoder.sv rtl/sfa_array.sv \
    rtl/sfa_otp_fsm.sv rtl/sfa_bank_scrub.sv rtl/sfa_eppa.sv rtl/sfa_top.sv \
    tb/sfa_top_tb.sv --top-module sfa_top_tb -o Vsfa_top_tb
./obj_dir/Vsfa_top_tb
```

### Using Icarus Verilog (Alternative)
```bash
cd models/spatial_fission
iverilog -g2012 -o tb/sfa_top_tb.vvp rtl/*.sv tb/sfa_top_tb.sv
vvp tb/sfa_top_tb.vvp
```
