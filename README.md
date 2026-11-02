# PolyFlow-NPU: Polymorphic-Dataflow Fissionable Systolic Array
### *Concurrent Multi-Tenant Architecture with Independent Per-Region Dataflows & Scalable Arrays (4×4, 8×8, 16×16)*

---

## 1. Executive Summary & Core Novel Idea

Modern deep learning workloads in edge intelligence, autonomous robotics, and multi-tenant datacenter inference demand **spatial multi-tenancy** (concurrent execution of independent models) alongside **multi-modal workload heterogeneity** (concurrent processing of Convolutional backbones, Transformer Self-Attention, and Depthwise Convolutions).

### The Fundamental Literature Gap
Prior deep learning accelerators force a mutually exclusive architectural compromise:
1. **Homogeneous Spatial Fission (e.g., Planaria, MICRO'20):** Dynamically partitions a physical systolic array into sub-arrays for concurrent multi-tenancy, but **locks all partitions to a single, rigid dataflow—predominantly Weight-Stationary (WS)**. When a partition executes a Transformer Self-Attention layer ($Q \cdot K^T$), it suffers severe energy and memory traffic overhead because WS is mathematically ill-suited for transient activation-activation multiplications.
2. **Single-Tenant Dataflow Switching (e.g., ReDas, IEEE TC'24):** Allows runtime switching across Weight-Stationary (WS), Output-Stationary (OS), and Input-Stationary (IS), but **operates exclusively on a single tenant across the entire physical array**. Multi-model workloads must queue serially, causing Head-of-Line (HoL) blocking and poor hardware utilization on small-to-medium models.

### Our Solution: Heterogeneous Fission (PolyFlow-NPU)
PolyFlow-NPU unifies both paradigms for the first time:
$$\textbf{PolyFlow-NPU} = \textbf{Concurrent Spatial Multi-Tenancy} + \textbf{Independent Per-Region Polymorphic Dataflow Selection}$$

Each dynamically partitioned region independently selects its mathematically optimal dataflow at runtime:
* **Region A:** Executes a CNN backbone (ResNet/ConvNeXt) in **Weight-Stationary (WS)** mode.
* **Region B:** Concurrently executes Transformer Self-Attention in **Output-Stationary (OS)** mode on the exact same clock cycles.
* **Hardware Isolation & Memory Safety:** Enforced via dynamic systolic boundary zeroing, an Event-Driven Phase-Pinned Arbiter (**EPPA**), and a **4-cycle mandatory zeroing scrub** with decentralized single-writer ownership tokens (**OTP**).

---

## 2. Microarchitectural Innovations

<p align="center">
  <img src="figures/polyflow_arch.png" alt="PolyFlow-NPU Microarchitecture Diagram" width="100%">
</p>

### 2.1 Two-Stage Pipelined MAC with 3:2 Carry-Save Accumulator (CSA)
In conventional single-cycle systolic PEs, recursive 32-bit accumulation after an $8 \times 8$ multiplier creates a critical delay path exceeding $4.2\text{ ns}$ in 90nm bulk CMOS. PolyFlow-NPU eliminates this bottleneck:
1. **Stage 1 (Multiply & Register):** Multiplies runtime-selected operands (`mul_a * mul_b`) and latches the 16-bit signed product into `product_reg`.
2. **Stage 2 (Redundant Carry-Save Accumulator):** Accumulation loop operates on two redundant 32-bit state vectors (`acc_sum` and `acc_carry`) using parallel 3:2 full adder compressors.
   * **$O(1)$ Gate Delay:** Carry rippling is completely eliminated from the inner feedback loop ($\approx 0.15\text{ ns}$ full adder delay).
   * **Readout Resolution:** Full carry propagation (`acc_out = acc_sum + acc_carry`) is deferred to final tile readout outside the high-frequency clock path, achieving **$+1.200\text{ ns}$ positive setup slack** at 200 MHz in Cadence Innovus ($f_{\text{max}} \approx 263.2\text{ MHz}$).

### 2.2 Dynamic Spatial Fission & Boundary Isolation
* The 2D mesh is split at runtime via `cfg_split_col` into independent sub-arrays.
* Inter-region horizontal forwarding wires are actively severed and multiplexed with dedicated Western injection ports (`din_w_region_b`), preventing data leakage across tenant boundaries.

### 2.3 Event-Driven Phase-Pinned Memory Arbiter (EPPA)
* Workload execution phases are tagged with 2-bit indicators (`PH_BURST`, `PH_IDLE`, `PH_STREAM`, `PH_RECONFIG`).
* EPPA recomputes bandwidth allocations **only on phase transitions** and pins them quasi-statically, removing dynamic arbitration logic from the high-frequency clock tree.
* Stranded bandwidth from stationary compute phases (WS compute needing zero bandwidth) is automatically redirected to streaming co-tenants (OS attention streams).

### 2.4 4-Cycle Mandatory Hardware Memory Scrubbing
* Prevents cross-tenant weight/activation snooping during memory bank migration.
* A deterministic hardware FSM clamps shared buses, flushes internal bank pipeline registers, and emits a single-cycle `bank_role_clear` strobe before granting ownership to the incoming tenant.

---

## 3. The Three Architectural Exploration Models

To benchmark each contribution systematically, this repository provides three self-contained models across multiple array dimensions:

| Model Directory | Architectural Configuration | Multi-Tenancy | Per-Region Dataflow | Key Workload Fit |
|---|---|:---:|:---:|---|
| [**`models/pipelined/dataflow_switching/`**](models/pipelined/dataflow_switching) | **Configuration B**<br/>*(ReDas Baseline)* | Single Tenant Only | Global WS ⇄ OS ⇄ IS | Single-model sequential layer execution |
| [**`models/pipelined/spatial_fission/`**](models/pipelined/spatial_fission) | **Configuration A**<br/>*(Planaria Baseline)* | Multi-Tenant (Region A + B) | Rigidly Locked to WS | Concurrent CNN workloads |
| [**`models/pipelined/heterogeneous_fission/`**](models/pipelined/heterogeneous_fission) | **Configuration C**<br/>*(Novel Proposed Idea)* | **Multi-Tenant (Region A + B)** | **Independent Runtime WS / OS / IS** | **Simultaneous CNN (WS) + Transformer (OS) co-execution** |

---

## 4. Array Scaling Exploration (4×4, 8×8, 16×16)

The core RTL modules are parameterized to enable physical design scaling across array dimensions:

| Array Dimensions | Processing Elements | Flip-Flop Count (PE Array) | Memory Banks | Column Split Width (`SPLIT_W`) | Drain Window (`LIFETIME_W`) |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **$4 \times 4$** *(Baseline)* | 16 PEs | 1,504 flops | 2 Banks | 4 bits (`[3:0]`) | 4 bits (15 cycles) |
| **$8 \times 8$** *(Scaled Pod)* | 64 PEs | 6,016 flops | 2 Banks | 4 bits (`[3:0]`) | 4 bits (15 cycles) |
| **$16 \times 16$** *(Full Pod)* | 256 PEs | 24,064 flops | 4 Banks | 5 bits (`[4:0]`) | 5 bits (31 cycles) |

### Key Architectural Upgrades for Scaled Arrays:
1. **Parameterized Fission Decoder:** `SPLIT_W` scales as `($clog2(NUM_COLS + 1) >= 4) ? $clog2(NUM_COLS + 1) : 4`, allowing 16-column partitions without overflow.
2. **Scalable Multi-Bank Clear Routing:** Dynamic `region_bank_clear` logic routes bank completion pulses to region owners across arbitrary bank counts (2, 4, 8).
3. **Column 0 Boundary Multiplexing:** Correctly routes `din_w_region_b` even during extreme partitions where `cfg_split_col = 0` (entire array allocated to Region B).
4. **Dedicated Scaled Top Wrappers:** Standalone top wrappers (`dfs_top_8x8`, `dfs_top_16x16`, `sfa_top_8x8`, `sfa_top_16x16`, `hdf_top_8x8`, `hdf_top_16x16`) for direct elaboration in Cadence Genus and Innovus.

---

## 5. Repository Directory Structure

```
mt_npu/
├── figures/                              # Publication-grade architectural diagrams (PNG)
│   ├── polyflow_arch.png                 # Master PolyFlow-NPU microarchitecture diagram
│   ├── fig0_comparison.png               # Side-by-side taxonomy & comparative matrix
│   ├── figA_homo_fission.png             # Configuration A: Homogeneous Fission Pod
│   ├── figB_seq_switch.png               # Configuration B: Sequential Dataflow Switching Pod
│   └── figC_hetero_fission.png           # Configuration C: Heterogeneous Fission Pod
│
├── models/                               # Architectural exploration models
│   ├── common.mk                         # Unified compilation, simulation & synthesis make rules
│   │
│   ├── pipelined/                        # [Pipelined Models] Two-Stage MAC + Carry-Save Accumulator
│   │   ├── dataflow_switching/           # Model 1: Single-tenant runtime WS/OS/IS switching
│   │   │   ├── rtl/                      # dfs_pe.sv, dfs_array.sv, dfs_top.sv, dfs_top_8x8.sv, dfs_top_16x16.sv
│   │   │   ├── tb/                       # dfs_top_tb.sv, dfs_top_8x8_tb.sv, dfs_top_16x16_tb.sv
│   │   │   └── Makefile                  # Compilation & synthesis targets
│   │   │
│   │   ├── spatial_fission/              # Model 2: Homogeneous spatial multi-tenancy
│   │   │   ├── rtl/                      # sfa_pe.sv, sfa_array.sv, sfa_top.sv, sfa_top_8x8.sv, sfa_top_16x16.sv
│   │   │   ├── tb/                       # sfa_top_tb.sv, sfa_top_8x8_tb.sv, sfa_top_16x16_tb.sv
│   │   │   └── Makefile                  # Compilation & synthesis targets
│   │   │
│   │   └── heterogeneous_fission/        # Model 3: Heterogeneous Fission (PolyFlow-NPU)
│   │       ├── rtl/                      # hdf_pe.sv, hdf_array_grid.sv, hdf_top.sv, hdf_top_8x8.sv, hdf_top_16x16.sv,
│   │       │                             # eppa_arbiter.sv, otp_token_fsm.sv, pod_bank_scrub.sv
│   │       ├── tb/                       # hdf_top_tb.sv, hdf_top_8x8_tb.sv, hdf_top_16x16_tb.sv
│   │       └── Makefile                  # Compilation & synthesis targets
│   │
│   └── non_pipelined/                    # [Non-Pipelined Models] Combinational MAC baselines
│
├── scripts/
│   ├── genus_synth.tcl                   # Cadence Genus ASIC logic synthesis reference script
│   └── innovus_pnr.tcl                   # Cadence Innovus PnR reference script
│
├── local/                                # Private scratchpads & reports (gitignored)
├── Makefile                              # Top-level master automation Makefile
├── .gitignore                            # Excludes logs, simulation sandboxes, and local documents
└── README.md                             # Global repository documentation (this file)
```

---

## 6. Verification & Simulation Guide

### 6.1 Fast Multi-Size Verification (Icarus Verilog)
Run cycle-accurate SystemVerilog testbenches verifying corner PEs, boundary isolation, and memory scrubbing:

```bash
# Verify ALL 3 models across ALL 3 array sizes (4x4, 8x8, 16x16 — 9 testsuites):
make test-scaling-all

# Or verify individual models across all sizes:
make test-scaling-model1    # Dataflow Switching (4x4, 8x8, 16x16)
make test-scaling-model2    # Spatial Fission (4x4, 8x8, 16x16)
make test-scaling-model3    # Heterogeneous Fission (4x4, 8x8, 16x16)

# Or test a specific configuration directly:
cd models/pipelined/heterogeneous_fission
make test-4x4               # 16-PE baseline
make test-8x8               # 64-PE scaled pod
make test-16x16             # 256-PE full pod
```

### 6.2 Cadence Xcelium Simulation
```bash
# Headless batch mode:
make run-model1
make run-model2
make run-model3

# Interactive SimVision GUI mode:
make gui-model3
```

### 6.3 Verilator C++ Cycle Simulation
```bash
make verilator-model1
make verilator-model2
make verilator-model3
```

---

## 7. Cadence Digital ASIC Implementation Flow (90nm)

The designs are synthesized and placed-and-routed using **Cadence Genus Synthesis Solution** and **Cadence Innovus Implementation System** targeting a 90nm bulk CMOS standard-cell library (`slow.lib` / `fast.lib` MMMC corners):

### 7.1 Logic Synthesis (Cadence Genus)
```bash
make synth-model1           # Synthesizes Model 1 (dataflow switching)
make synth-model2           # Synthesizes Model 2 (spatial fission)
make synth-model3           # Synthesizes Model 3 (heterogeneous fission)
make synth-all              # Synthesizes all 3 models sequentially
```

* **Timing Constraints:** $T_{\text{clk}} = 5.000\text{ ns}$ ($200\text{ MHz}$ target), clock uncertainty $0.050\text{ ns}$, input/output delay $0.500\text{ ns}$.
* **Multicycle Paths:** Configured for dispatch-time configuration registers (`region_id_mask`).

### 7.2 Physical Design: Place-and-Route (Cadence Innovus)
```bash
make pnr-place-model1       # Floorplan, power routing, placement, CTS & routing
make pnr-place-model2
make pnr-place-model3
```

* **Technology & Metal Stack:** Standard 90nm 7-metal grid (`M1`–`M7`), `gsclib090site` core site.
* **Clock Tree Synthesis (CCOpt):** Balanced clock DAG with 15 clock buffers, zero clock gating violations, and target insertion delay $<0.65\text{ ns}$.
* **Post-Route Timing Slack:** Achieves **$+1.200\text{ ns}$ setup slack** ($f_{\text{max}} \approx 263.2\text{ MHz}$) due to the two-stage pipelined datapath and redundant carry-save accumulator.

---

## 8. Git Branching Strategy

| Branch | Status | Purpose |
| :--- | :---: | :--- |
| **`main`** | `LOCKED` | Verified $4 \times 4$ baseline deliverables, synthesis checkpoints, and Review-3 defense artifacts. |
| **`feat/npu-array-scaling`** | `ACTIVE` | Parameterized array scaling ($8 \times 8$, $16 \times 16$), fission microarchitecture upgrades, and scalability benchmarks. |
