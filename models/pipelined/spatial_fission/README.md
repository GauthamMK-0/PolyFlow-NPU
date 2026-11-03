# Model 2: Homogeneous Spatial Fission Architecture (Pipelined)

## 1. Overview
This directory contains the standalone **Spatial Fission Model** (corresponding to **Configuration A** in `evaluation_framework.md` / Planaria-style architecture).

### Architectural Characteristics
* **Spatial Multi-Tenancy (Fission):** A single physical PE array is dynamically partitioned into two independently operating regions (Region A and Region B) via dispatch-time column splitting (`cfg_split_col`).
* **Hardware Boundary Isolation:** Inter-region horizontal forwarding wires are dynamically forced to zero at column boundaries, preventing cross-tenant operand bleeding.
* **Homogeneous Dataflow Constraint:** All partitioned regions are locked to the same global dataflow (**Weight-Stationary**). This captures the fundamental limitation of prior spatial multi-tenant accelerators.
* **Shared Memory Substrate:** Memory banks are arbitrated via:
  - Single-writer ownership token protocol (**OTP**) with rotating epoch priority.
  - Mandatory **4-cycle hardware zeroing scrub controller** before bank role migration.
  - Event-driven phase-pinned memory bandwidth arbiter (**EPPA**).
* **Two-Stage Pipelined MAC:** Eliminates recursive accumulation delay bottlenecks using registered product stages and redundant carry-save accumulator (CSA) loops.

---

## 2. Directory Structure & Partitioned Scaling Layout
```
models/pipelined/spatial_fission/
├── rtl/
│   ├── sfa_pe.sv              # Processing element pinned to Weight-Stationary with CSA
│   ├── sfa_fission_decoder.sv # Dynamic column split decoder
│   ├── sfa_array.sv           # Parameterized 2D systolic array with hardware boundary isolation
│   ├── sfa_otp_fsm.sv         # Single-writer ownership token FSM
│   ├── sfa_bank_scrub.sv      # 4-cycle zeroing scrub controller
│   ├── sfa_eppa.sv            # Event-driven phase-pinned bandwidth arbiter
│   ├── sfa_top.sv             # Top-level multi-tenant pod (parameterized default 4x4)
│   ├── sfa_top_8x8.sv         # Dedicated 8x8 scaled pod wrapper
│   └── sfa_top_16x16.sv       # Dedicated 16x16 full pod wrapper
├── tb/
│   ├── sfa_top_tb.sv          # 4x4 baseline testbench
│   ├── sfa_top_8x8_tb.sv      # 8x8 scaled pod testbench (64 PEs)
│   └── sfa_top_16x16_tb.sv    # 16x16 full pod testbench (256 PEs)
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

## 3. Scalable Array Configurations (4x4, 8x8, 16x16)

Model 2 supports parameterized array dimensions configured via `SCALE`:

| Dimension | Processing Elements | Memory Banks | Split Width (`SPLIT_W`) | INT8 Throughput (@ 200 MHz) | Primary Testbench |
| :---: | :---: | :---: | :---: | :---: | :--- |
| **4x4** (Baseline) | 16 PEs | 2 Banks | 4 bits (`[3:0]`) | 6.4 GOPS | `tb/sfa_top_tb.sv` |
| **8x8** (Scaled Pod) | 64 PEs | 2 Banks | 4 bits (`[3:0]`) | 25.6 GOPS | `tb/sfa_top_8x8_tb.sv` |
| **16x16** (Full Pod) | 256 PEs | 4 Banks | 5 bits (`[4:0]`) | 102.4 GOPS | `tb/sfa_top_16x16_tb.sv` |

---

## 4. Verification & Simulation

### Testbench Architecture
The testbenches validate concurrent multi-tenancy and shared resource arbitration:
1. **Dynamic Column Partitioning:** Tests dynamic column splits (e.g. `cfg_split_col = 2` on 4x4, `4` on 8x8, `8` on 16x16) and verifies `region_id_mask`.
2. **Concurrent WS Co-Execution:** Executes Region A and Region B concurrently across the partitioned boundary, verifying correct mathematical results in both regions.
3. **EPPA Memory Bandwidth Arbitration:** Validates dynamic bandwidth allocation across differing tenant memory phases.
4. **Shared Memory Scrubbing:** Validates the 4-cycle hardware zeroing scrub sequence and `bank_role_clear` handshake.

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

Model 2 is configured for multi-scale logic synthesis mapped to standard cells (`slow.lib`) using Cadence Genus:

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
- **Boundary Optimization**: Pre-decoded boundary column flags (`is_boundary_col`) eliminate row-level boundary MUX delays
- **Timing Headroom**: Single-cycle datapath achieves robust positive setup slack ($\ge +1.5\text{ ns}$) across all paths

---

## 6. Physical Design & Implementation (Cadence Innovus)

Model 2 includes a complete physical design flow (Floorplanning, Power Grid, Placement, CTS, Detailed Routing, Signoff):

```bash
make pnr-place-4x4      # Complete PnR flow for 4x4 (outputs in outputs/4x4/, db/4x4/)
make pnr-place-8x8      # Complete PnR flow for 8x8 (outputs in outputs/8x8/, db/8x8/)
make pnr-place-16x16    # Complete PnR flow for 16x16 (outputs in outputs/16x16/, db/16x16/)
make pnr-place-scaling  # PnR across all scales
```

- **Standard Cell Library**: 90nm bulk CMOS (`gsclib090_translated.lef`)
- **Clock Tree Synthesis**: CCOpt clock tree engine with non-default NDR rules (`2w2s`)
- **Deliverables**: Placed & routed DEF (`outputs/${SCALE}/sfa_top_postroute.def`), signoff netlist, and SDF timing files.
