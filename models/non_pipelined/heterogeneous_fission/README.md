# Model 3: Heterogeneous-Dataflow Fissionable Systolic Array (Non-Pipelined Baseline)

## 1. Overview
This directory contains the **Non-Pipelined Combinational Baseline** of our Heterogeneous Fission Architecture (PolyFlow-NPU / Configuration C).

### Key Architectural Characteristics
* **Concurrent Spatial Multi-Tenancy:** The physical systolic array dynamically divides into independent execution regions (Region A and Region B) at dispatch time via `cfg_split_col`.
* **Independent Per-Region Dataflow Freedom:** Each region independently selects its mathematically optimal dataflow at runtime:
  - **Region A:** Can run a CNN backbone in **Weight-Stationary (WS)** mode.
  - **Region B:** Can simultaneously run Transformer Self-Attention in **Output-Stationary (OS)** mode.
* **Single-Cycle Combinational MAC Baseline:** Implements single-cycle combinational multiplier-accumulator logic, serving as the timing, power, and area baseline to quantify the performance and clock frequency gains offered by the pipelined carry-save accumulator (CSA) design.
* **Hardware Boundary Isolation:** Inter-region systolic mesh connections are zeroed at runtime, preventing cross-tenant operand bleeding.
* **Phase-Driven Memory Bandwidth Arbiter (EPPA):** Quasi-static bandwidth allocation driven by tenant execution phases (`BURST` vs `STREAM`).
* **Decentralized Memory Ownership & Anti-Leakage (OTP + Scrub):** Single-writer ownership token protocol with epoch-rotating priority and 4-cycle hardware zeroing scrub.

---

## 2. Directory Structure & Partitioned Scaling Layout
```
models/non_pipelined/heterogeneous_fission/
├── rtl/
│   ├── hdf_pe.sv              # Heterogeneous PE with WS/OS/IS (combinational MAC)
│   ├── hdf_fission_decoder.sv # Dynamic column partition decoder
│   ├── hdf_array_grid.sv      # 2D array grid with dynamic boundary isolation
│   ├── eppa_arbiter.sv        # Event-driven phase-pinned bandwidth arbiter
│   ├── otp_token_fsm.sv       # Single-writer ownership token FSM
│   ├── pod_bank_scrub.sv      # 4-cycle zeroing scrub controller
│   └── hdf_top.sv             # Top-level unified heterogeneous fission pod (4x4 baseline)
├── tb/
│   └── hdf_top_tb.sv          # Standalone SystemVerilog co-execution testbench
├── reports/                   # Cadence Genus & Innovus synthesis/PnR reports
│   ├── 4x4/                   # 4x4 baseline reports (timing, area, power, qor, gates)
│   ├── 8x8/                   # 8x8 scaled pod reports
│   ├── 16x16/                 # 16x16 full pod reports
│   └── cts/                   # Clock Tree Synthesis reports
├── netlist/                   # Gate-level netlists & timing models
│   ├── 4x4/                   # hdf_top_netlist.v, .sdc, .sdf for 4x4
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
├── hdf_top.sdc                # SDC timing constraints (200 MHz / 5.000 ns clock target)
├── synth_hdf.tcl              # Multi-scale Cadence Genus synthesis script
├── pnr_place_hdf.tcl          # Multi-scale Cadence Innovus physical design script
├── Makefile                   # Automation Makefile for simulation, synthesis, and PnR
└── README.md
```

---

## 3. Verification & Simulation

### Simulation Commands
```bash
# Fast Icarus Verilog simulation:
make test-4x4       # Run 4x4 baseline simulation (output in output/4x4/)
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

## 4. ASIC Logic Synthesis & Physical Design (90nm)

```bash
# Cadence Genus logic synthesis:
make synth-4x4          # Synthesize 4x4 netlist and reports (reports/4x4/, netlist/4x4/)

# Cadence Innovus physical design:
make pnr-place-4x4      # Complete PnR flow for 4x4 (outputs in outputs/4x4/, db/4x4/)
```
