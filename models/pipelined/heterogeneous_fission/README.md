# Model 3: Heterogeneous-Dataflow Fissionable Systolic Array (PolyFlow-NPU)

## Overview
This directory contains our **Novel Proposed Architecture** (PolyFlow-NPU / Configuration C).

### Key Innovations
1. **Concurrent Spatial Multi-Tenancy:** The systolic array dynamically divides into independent execution regions (Region A and Region B) at dispatch time via `cfg_split_col`.
2. **Independent Per-Region Dataflow Freedom:** Unlike prior spatial accelerators (e.g. Planaria) that freeze all sub-arrays into Weight-Stationary, each region independently selects its mathematically optimal dataflow at runtime:
   - **Region A:** Can run a CNN backbone in **Weight-Stationary (WS)** mode.
   - **Region B:** Can simultaneously run Transformer Self-Attention in **Output-Stationary (OS)** mode.
3. **Hardware Boundary Isolation:** Inter-region systolic mesh connections are zeroed at runtime, preventing cross-tenant operand bleeding.
4. **Phase-Driven Memory Bandwidth Arbiter (EPPA):** Arbitrates memory bandwidth only on phase transitions (`BURST`, `IDLE`, `STREAM`, `RECONFIG`) and pins the allocation quasi-statically, taking arbitration off the high-frequency clock path.
5. **Decentralized Memory Ownership & Anti-Leakage (OTP + Scrub):**
   - Single-writer ownership token protocol with epoch-rotating priority guarantees mutual exclusion without starvation or side-channel leakage.
   - Mandatory 4-cycle hardware zeroing scrub clears residual tenant data before releasing memory banks to new owners.
6. **Lifetime Counter:** Gates MAC execution during boundary shifts, gracefully draining in-flight partial sums.

---

## Directory Structure
```
models/pipelined/heterogeneous_fission/
├── rtl/
│   ├── hdf_pe.sv              # Heterogeneous PE with WS/OS/IS, lifetime counter, stale flag
│   ├── hdf_fission_decoder.sv # Dynamic column partition decoder
│   ├── hdf_array_grid.sv      # 2D array grid with dynamic boundary isolation
│   ├── eppa_arbiter.sv        # Event-driven phase-pinned bandwidth arbiter
│   ├── otp_token_fsm.sv       # Single-writer ownership token FSM
│   ├── pod_bank_scrub.sv      # 4-cycle zeroing scrub controller
│   └── hdf_top.sv             # Top-level unified heterogeneous fission pod
├── tb/
│   └── hdf_top_tb.sv          # Standalone SystemVerilog co-execution testbench
├── hdf_top.sdc                # SDC timing constraints (200 MHz / 5.000 ns clock target)
├── synth_hdf.tcl              # Cadence Genus synthesis execution script
├── Makefile                   # Cadence Xcelium & Genus automation
└── README.md
```

---

## Verification & Simulation

### Testbench Architecture (`tb/hdf_top_tb.sv`)
The self-contained SystemVerilog testbench validates the core architectural features:
1. **Dynamic Column Partitioning:** Slices array at column 2 and verifies `region_id_mask = 1100`.
2. **Concurrent Heterogeneous Execution:** Simultaneously executes Region A in Weight-Stationary (WS) mode and Region B in Output-Stationary (OS) mode with verified mathematical correctness.
3. **EPPA Memory Bandwidth Arbitration:** Arbitrates bandwidth dynamically based on phase profiles (`BURST` vs `STREAM`).
4. **Memory Bank Ownership Migration & Scrubbing:** Validates the 4-cycle hardware zeroing scrub sequence and `bank_role_clear` handshake.

### Simulation Commands
```bash
cd models/pipelined/heterogeneous_fission
make run         # Cadence Xcelium simulation (default, headless)
make gui         # Cadence Xcelium with SimVision GUI
make iverilog    # Fast simulation using Icarus Verilog (< 1s)
make verilator   # Cycle-accurate simulation using Verilator
make lint        # Strict Verilator linting (-Wall --timing)
make clean       # Clean simulation sandbox and log files
```

---

## ASIC Logic Synthesis & Timing Closure (Cadence Genus @ 200 MHz)

Model 3 is pre-configured for logic synthesis mapped to standard cells (`slow.lib`) using Cadence Genus:

```bash
cd models/pipelined/heterogeneous_fission
make synth            # Runs genus with synth_hdf.tcl and hdf_top.sdc
```

### Synthesis Specifications & Optimizations
- **Target Frequency**: **200 MHz** ($T_{\text{clk}} = 5.000\text{ ns}$)
- **I/O Delay Budget**: $0.500\text{ ns}$ (10% of clock period)
- **Clock Uncertainty**: $0.050\text{ ns}$ (setup margin)
- **Timing Model**: Pure standard single-cycle synchronous STA across all paths (no multicycle paths or false path exceptions needed)
- **Synthesis Effort**: Clean, standard synthesis flow (`syn_generic`, `syn_map`, `syn_opt` at `medium` effort) without artificial datapath sharing or forced flattening
- **Timing Headroom**: Single-cycle datapath achieves robust positive setup slack ($\ge +1.5\text{ ns}$) across all register-to-register and I/O paths


