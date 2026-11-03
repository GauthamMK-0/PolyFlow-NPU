# Model 3: Heterogeneous-Dataflow Fissionable Systolic Array (PolyFlow-NPU)

## 1. Overview
This directory contains our **Novel Proposed Architecture** (PolyFlow-NPU / Configuration C).

### Key Innovations
1. **Concurrent Spatial Multi-Tenancy:** The physical systolic array dynamically divides into independent execution regions (Region A and Region B) at dispatch time via `cfg_split_col`.
2. **Independent Per-Region Dataflow Freedom:** Unlike prior spatial accelerators (e.g. Planaria) that freeze all sub-arrays into Weight-Stationary, each region independently selects its mathematically optimal dataflow at runtime:
   - **Region A:** Can run a CNN backbone in **Weight-Stationary (WS)** mode.
   - **Region B:** Can simultaneously run Transformer Self-Attention in **Output-Stationary (OS)** mode on the exact same clock cycles.
3. **Two-Stage Pipelined MAC with 3:2 Carry-Save Accumulator (CSA):**
   - **Stage 1 (Product Generation):** Registers the 16-bit signed product (`mul_a * mul_b`).
   - **Stage 2 (Redundant Accumulation):** Employs dual 32-bit state vectors (`acc_sum` and `acc_carry`) with parallel 3:2 compressor adders, eliminating carry rippling from the feedback loop and providing $+1.200\text{ ns}$ setup slack at 200 MHz.
4. **Hardware Boundary Isolation:** Inter-region systolic mesh connections are zeroed at runtime, preventing cross-tenant operand bleeding.
5. **Phase-Driven Memory Bandwidth Arbiter (EPPA):** Arbitrates memory bandwidth only on phase transitions (`BURST`, `IDLE`, `STREAM`, `RECONFIG`) and pins allocations quasi-statically, taking dynamic arbitration off the high-frequency clock path.
6. **Decentralized Memory Ownership & Anti-Leakage (OTP + Scrub):**
   - Single-writer ownership token protocol with epoch-rotating priority guarantees mutual exclusion without starvation or side-channel leakage.
   - Mandatory 4-cycle hardware zeroing scrub clears residual tenant data before releasing memory banks to new owners.
7. **Lifetime Counter:** Gates MAC execution during boundary shifts, gracefully draining in-flight partial sums.

---

## 2. Directory Structure & Partitioned Scaling Layout
```
models/pipelined/heterogeneous_fission/
├── rtl/
│   ├── hdf_pe.sv              # Heterogeneous PE with WS/OS/IS, CSA accumulator, lifetime counter
│   ├── hdf_fission_decoder.sv # Parameterized dynamic column partition decoder
│   ├── hdf_array_grid.sv      # Parameterized 2D array grid with dynamic boundary isolation
│   ├── eppa_arbiter.sv        # Event-driven phase-pinned bandwidth arbiter
│   ├── otp_token_fsm.sv       # Single-writer ownership token FSM
│   ├── pod_bank_scrub.sv      # 4-cycle zeroing scrub controller
│   ├── hdf_top.sv             # Top-level unified heterogeneous fission pod (parameterized default 4x4)
│   ├── hdf_top_8x8.sv         # Dedicated 8x8 scaled pod wrapper
│   └── hdf_top_16x16.sv       # Dedicated 16x16 full pod wrapper
├── tb/
│   ├── hdf_top_tb.sv          # 4x4 baseline co-execution testbench
│   ├── hdf_top_8x8_tb.sv      # 8x8 scaled pod co-execution testbench (64 PEs)
│   └── hdf_top_16x16_tb.sv    # 16x16 full pod co-execution testbench (256 PEs)
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

## 3. Scalable Array Configurations (4x4, 8x8, 16x16)

Model 3 supports parameterized array scaling via `SCALE`:

| Dimension | Processing Elements | Flip-Flop Count | Memory Banks | Split Width (`SPLIT_W`) | Drain Window (`LIFETIME_W`) | INT8 Throughput (@ 200 MHz) | Primary Testbench |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **4x4** (Baseline) | 16 PEs | 1,504 flops | 2 Banks | 4 bits (`[3:0]`) | 4 bits (15 cyc) | 6.4 GOPS | `tb/hdf_top_tb.sv` |
| **8x8** (Scaled Pod) | 64 PEs | 6,016 flops | 2 Banks | 4 bits (`[3:0]`) | 4 bits (15 cyc) | 25.6 GOPS | `tb/hdf_top_8x8_tb.sv` |
| **16x16** (Full Pod) | 256 PEs | 24,064 flops | 4 Banks | 5 bits (`[4:0]`) | 5 bits (31 cyc) | 102.4 GOPS | `tb/hdf_top_16x16_tb.sv` |

---

## 4. Verification & Simulation

### Testbench Architecture
The testbenches validate concurrent heterogeneous multi-tenancy:
1. **Dynamic Column Partitioning:** Configures split column and verifies `region_id_mask`.
2. **Concurrent Heterogeneous Co-Execution:** Simultaneously executes Region A in Weight-Stationary (WS) mode and Region B in Output-Stationary (OS) mode with verified mathematical correctness.
3. **EPPA Memory Bandwidth Arbitration:** Dynamically arbitrates bandwidth based on phase profiles (`BURST` vs `STREAM`).
4. **Memory Bank Ownership Migration & Scrubbing:** Validates the 4-cycle hardware zeroing scrub sequence and `bank_role_clear` handshake.

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

Model 3 is configured for multi-scale logic synthesis mapped to standard cells (`slow.lib`) using Cadence Genus:

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
- **Timing Headroom**: Two-stage MAC architecture with carry-save compressor loops achieves robust positive setup slack ($\ge +1.5\text{ ns}$) across all paths

---

## 6. Physical Design & Implementation (Cadence Innovus)

Model 3 includes a complete physical design flow (Floorplanning, Power Grid, Placement, CTS, Detailed Routing, Signoff):

```bash
make pnr-place-4x4      # Complete PnR flow for 4x4 (outputs in outputs/4x4/, db/4x4/)
make pnr-place-8x8      # Complete PnR flow for 8x8 (outputs in outputs/8x8/, db/8x8/)
make pnr-place-16x16    # Complete PnR flow for 16x16 (outputs in outputs/16x16/, db/16x16/)
make pnr-place-scaling  # PnR across all scales
```

- **Standard Cell Library**: 90nm bulk CMOS (`gsclib090_translated.lef`)
- **Clock Tree Synthesis**: CCOpt clock tree engine with non-default NDR rules (`2w2s`)
- **Deliverables**: Placed & routed DEF (`outputs/${SCALE}/hdf_top_postroute.def`), signoff netlist, and SDF timing files.
