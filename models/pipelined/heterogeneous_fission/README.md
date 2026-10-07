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
models/heterogeneous_fission/
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
└── README.md
```

---

## Verification & Simulation

### Test Suite & Verification Matrix
The test harness (`tb/hdf_top_tb.sv`) implements a modular hybrid verification architecture:
- `test_split_partition.svh`: Dynamic dispatch-time column partitioning (Cols 0-1: Reg A, Cols 2-3: Reg B).
- `test_hetero_coexec.svh`: Heterogeneous co-execution across WS+OS, IS+WS, and OS+IS dataflow pairs.
- `test_eppa_phase_arb.svh`: EPPA memory bandwidth allocation across BURST, STREAM, IDLE, and RECONFIG phases with urgency flags.
- `test_mem_scrub_migration.svh`: Memory bank migration with mandatory 4-cycle hardware zeroing scrub.
- `test_corner_lifetime_expiry.svh`: Tenant hardware lifetime expiration countdown and automatic PE compute clamping.
- `test_corner_bank_contention.svh`: Concurrent multi-tenant memory bank contention with mutual exclusion and starvation avoidance.
- `test_corner_reconfig_split.svh`: Dynamic online array fission across boundary columns 0, 1, 2, 3, 4.
- `test_random_stimulus.svh`: Constrained-random stimulus with automated self-checking against a golden mathematical model.
- `hdf_coverage_monitor.svh`: Dual-compatible functional coverage engine with IEEE 1800 covergroups for Cadence IMC and active bin tracker (**30 / 30 bins = 100.0% coverage**).

### Using Cadence Xcelium (xrun)
```bash
cd models/pipelined/heterogeneous_fission
make run              # Headless batch mode (default)
make gui              # Interactive GUI mode with SimVision
make run TEST=coexec  # Run specific testcase (e.g. lifetime, contention, reconfig, random)
make clean            # Clean output/ sandbox and log files
```

### Using Verilator
```bash
cd models/pipelined/heterogeneous_fission
verilator -j $(nproc) --binary --timing -Wall -Itb -Itb/tests \
    rtl/*.sv tb/hdf_top_tb.sv --top-module hdf_top_tb -o Vhdf_top_tb
./obj_dir/Vhdf_top_tb +TEST=ALL
```

### Using Icarus Verilog (Alternative)
```bash
cd models/pipelined/heterogeneous_fission
iverilog -g2012 -I tb -I tb/tests -o tb/hdf_top_tb.vvp rtl/*.sv tb/hdf_top_tb.sv
vvp tb/hdf_top_tb.vvp +TEST=ALL
```
