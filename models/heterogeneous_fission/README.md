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
│   ├── hdf_pe.v              # Heterogeneous PE with WS/OS/IS, lifetime counter, stale flag
│   ├── hdf_fission_decoder.v # Dynamic column partition decoder
│   ├── hdf_array_grid.v      # 2D array grid with dynamic boundary isolation
│   ├── eppa_arbiter.v        # Event-driven phase-pinned bandwidth arbiter
│   ├── otp_token_fsm.v       # Single-writer ownership token FSM
│   ├── pod_bank_scrub.v      # 4-cycle zeroing scrub controller
│   └── hdf_top.v             # Top-level unified heterogeneous fission pod
├── tb/
│   └── hdf_top_tb.v          # Standalone SystemVerilog co-execution testbench
└── README.md
```

---

## Verification & Simulation

### Using Verilator
```bash
cd models/heterogeneous_fission
verilator --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
    rtl/hdf_pe.v rtl/hdf_fission_decoder.v rtl/hdf_array_grid.v \
    rtl/eppa_arbiter.v rtl/otp_token_fsm.v rtl/pod_bank_scrub.v rtl/hdf_top.v \
    tb/hdf_top_tb.v --top-module hdf_top_tb -o Vhdf_top_tb
./obj_dir/Vhdf_top_tb
```

### Using Icarus Verilog (Alternative)
```bash
cd models/heterogeneous_fission
iverilog -g2012 -o tb/hdf_top_tb.vvp rtl/*.v tb/hdf_top_tb.v
vvp tb/hdf_top_tb.vvp
```
