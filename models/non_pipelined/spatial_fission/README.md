# Model 2: Homogeneous Spatial Fission Architecture (Non-Pipelined Baseline)

## 1. Overview
This directory contains the **Non-Pipelined Combinational Baseline** of the Spatial Fission Model (corresponding to **Configuration A** in `evaluation_framework.md` / Planaria-style architecture).

### Key Architectural Characteristics
* **Spatial Multi-Tenancy (Fission):** A single physical PE array is dynamically partitioned into two independently operating regions (Region A and Region B) via dispatch-time column splitting (`cfg_split_col`).
* **Hardware Boundary Isolation:** Inter-region horizontal forwarding wires are dynamically zeroed at column boundaries, preventing cross-tenant operand bleeding.
* **Homogeneous Dataflow Constraint:** All partitioned regions are locked to the same global dataflow (**Weight-Stationary**). This captures the fundamental limitation of prior spatial multi-tenant accelerators.
* **32-Bit Vertical Partial-Sum Mesh:** Vertical ports (`din_n` / `dout_s`) are widened to 32 bits (`ACC_W = 32`), providing bit-for-bit mathematical parity with the pipelined model without accumulator overflow.
* **Single-Cycle Combinational MAC Baseline:** Implements direct single-cycle multiplication and accumulation, serving as the architectural timing, power, and area baseline to quantify the performance and clock frequency gains offered by the pipelined carry-save accumulator (CSA) design.
* **Shared Memory Substrate:** Memory banks are arbitrated via:
  - Single-writer ownership token protocol (**OTP**) with rotating epoch priority.
  - Mandatory **4-cycle hardware zeroing scrub controller** before bank role migration.
  - Event-driven phase-pinned memory bandwidth arbiter (**EPPA**).

---

## 2. Directory Structure & Layout
```
models/non_pipelined/spatial_fission/
├── rtl/
│   ├── sfa_pe.sv              # Processing element pinned to Weight-Stationary (combinational MAC, 32-bit psum)
│   ├── sfa_fission_decoder.sv # Dynamic column split decoder
│   ├── sfa_array.sv           # 2D systolic array with hardware boundary isolation
│   ├── sfa_otp_fsm.sv         # Single-writer ownership token FSM
│   ├── sfa_bank_scrub.sv      # 4-cycle zeroing scrub controller
│   ├── sfa_eppa.sv            # Event-driven phase-pinned bandwidth arbiter
│   └── sfa_top.sv             # Top-level multi-tenant pod (4x4 baseline)
├── tb/
│   └── sfa_top_tb.sv          # Standalone SystemVerilog testbench (exhaustive 16 PEs)
├── reports/                   # Cadence Genus & Innovus synthesis/PnR reports
│   ├── 4x4/                   # 4x4 baseline reports (timing, area, power, qor, gates)
│   ├── 8x8/                   # 8x8 scaled pod reports
│   ├── 16x16/                 # 16x16 full pod reports
│   └── cts/                   # Clock Tree Synthesis reports
├── netlist/                   # Gate-level netlists & timing models
│   ├── 4x4/                   # sfa_top_netlist.v, .sdc, .sdf for 4x4
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
├── sfa_top.sdc                # SDC timing constraints (200 MHz / 5.000 ns clock target)
├── synth_sfa.tcl              # Multi-scale Cadence Genus synthesis script
├── pnr_place_sfa.tcl          # Multi-scale Cadence Innovus physical design script
├── Makefile                   # Automation Makefile for simulation, synthesis, and PnR
└── README.md
```

---

## 3. Verification & Simulation

### Testbench Architecture
The standalone testbench (`tb/sfa_top_tb.sv`) validates dynamic spatial fission and shared resource arbitration with **exhaustive 16-PE assertion coverage**:
1. **Dynamic Column Partitioning:** Confirms split decoding and boundary isolation mask (`region_id_mask`).
2. **Concurrent Multi-Tenant WS Execution:** Co-executes distinct matrix workloads in Region A and Region B simultaneously, verifying mathematical correctness across **100% of all 16 PEs** with combinational MACs.
3. **EPPA Memory Bandwidth Arbitration:** Dynamically arbitrates memory bandwidth across regions based on phase indicators (`BURST` vs `STREAM`).
4. **Memory Scrubbing & Handshakes:** Exercises the 4-cycle hardware scrub state machine and `bank_role_clear` ownership transfers.

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
