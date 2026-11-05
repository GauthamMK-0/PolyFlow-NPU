# PolyFlow-NPU: Polymorphic-Dataflow Fissionable Systolic Array
### Concurrent Multi-Tenant Architecture with Independent Per-Region Dataflows and Scalable Arrays (4x4, 8x8, 16x16)

---

## 1. Executive Summary and Core Novel Idea

Modern deep learning workloads in edge intelligence, autonomous robotics, and multi-tenant datacenter inference demand **spatial multi-tenancy** (concurrent execution of independent models) alongside **multi-modal workload heterogeneity** (concurrent processing of Convolutional backbones, Transformer Self-Attention, and Depthwise Convolutions).

### The Fundamental Literature Gap
Prior deep learning accelerators force a mutually exclusive architectural compromise:
1. **Homogeneous Spatial Fission (e.g., Planaria, MICRO'20):** Dynamically partitions a physical systolic array into sub-arrays for concurrent multi-tenancy, but **locks all partitions to a single, rigid dataflow -- predominantly Weight-Stationary (WS)**. When a partition executes a Transformer Self-Attention layer ($Q \cdot K^T$), it suffers severe energy and memory traffic overhead because WS is mathematically ill-suited for transient activation-activation multiplications.
2. **Single-Tenant Dataflow Switching (e.g., ReDas, IEEE TC'24):** Allows runtime switching across Weight-Stationary (WS), Output-Stationary (OS), and Input-Stationary (IS), but **operates exclusively on a single tenant across the entire physical array**. Multi-model workloads must queue serially, causing Head-of-Line (HoL) blocking and poor hardware utilization on small-to-medium models.

### Our Solution: Heterogeneous Fission (PolyFlow-NPU)
PolyFlow-NPU unifies both paradigms:

$$\text{PolyFlow-NPU} = \text{Concurrent Spatial Multi-Tenancy} + \text{Independent Per-Region Polymorphic Dataflow Selection}$$

Each dynamically partitioned region independently selects its mathematically optimal dataflow at runtime:
- **Region A:** Executes a CNN backbone (ResNet/ConvNeXt) in **Weight-Stationary (WS)** mode.
- **Region B:** Concurrently executes Transformer Self-Attention in **Output-Stationary (OS)** mode on the exact same clock cycles.
- **Hardware Isolation and Memory Safety:** Enforced via dynamic systolic boundary zeroing, an Event-Driven Phase-Pinned Arbiter (**EPPA**), and a **4-cycle mandatory zeroing scrub** with decentralized single-writer ownership tokens (**OTP**).

---

## 2. Microarchitectural Innovations

<p align="center">
  <img src="figures/polyflow_arch.png" alt="PolyFlow-NPU Microarchitecture Diagram" width="100%">
</p>

### 2.1 32-Bit Vertical Partial-Sum Mesh & Registered Systolic Forwarding
- **Wide Accumulation Bus:** Vertical streaming ports (`din_n` / `dout_s`) are widened to 32 bits (`ACC_W = 32`), eliminating dynamic range overflow during multi-step matrix accumulation.
- **True Systolic Registering:** Every spatial hop between adjacent PEs is registered (`din_w_reg`, `dout_s_reg`), introducing exactly 1 clock cycle of latency per physical PE. This bounds the critical path within a single PE and eliminates combinational ripple loops.
- **West-to-East Weight Shift Preload:** Stationary weights are preloaded using the existing horizontal forwarding datapath as a shift register chain (`w_ld = 1`), eliminating high-fanout global broadcast bottlenecks.

### 2.2 Two-Stage Pipelined MAC with 3:2 Carry-Save Accumulator (CSA)
In conventional single-cycle systolic PEs, recursive 32-bit accumulation after an 8x8 multiplier creates a critical delay path exceeding 4.2 ns in 90nm bulk CMOS. PolyFlow-NPU eliminates this bottleneck:
1. **Stage 1 (Multiply and Register):** Multiplies runtime-selected operands (`mul_a * mul_b`) and latches the 16-bit signed product into `product_reg`. Control signals (`compute_pipe`, `df_mode_pipe`) are pipelined synchronously.
2. **Stage 2 (Redundant Carry-Save Accumulator):** The accumulation loop operates on two redundant 32-bit state vectors (`acc_sum` and `acc_carry`) using parallel 3:2 full adder compressors.
   - **$O(1)$ Gate Delay:** Carry rippling is completely eliminated from the inner feedback loop (~0.15 ns full adder delay).
   - **Readout Resolution:** Full carry propagation (`acc_out = acc_sum + acc_carry`) is deferred to final tile readout outside the high-frequency clock path, achieving **+1.200 ns positive setup slack** at 200 MHz in Cadence Innovus ($f_{\text{max}} \approx 263.2\text{ MHz}$).

### 2.3 Dynamic Spatial Fission and Boundary Isolation
- The 2D mesh is split at runtime via `cfg_split_col` into independent sub-arrays.
- Inter-region horizontal forwarding wires are actively severed and multiplexed with dedicated Western injection ports (`din_w_region_b`), preventing data leakage across tenant boundaries.

### 2.4 Event-Driven Phase-Pinned Memory Arbiter (EPPA)
- Workload execution phases are tagged with 2-bit indicators (`PH_BURST`, `PH_IDLE`, `PH_STREAM`, `PH_RECONFIG`).
- EPPA recomputes bandwidth allocations **only on phase transitions** and pins them quasi-statically, removing dynamic arbitration logic from the high-frequency clock tree.
- Stranded bandwidth from stationary compute phases (WS compute needing zero bandwidth) is automatically redirected to streaming co-tenants (OS attention streams).

### 2.5 4-Cycle Mandatory Hardware Memory Scrubbing
- Prevents cross-tenant weight/activation snooping during memory bank migration.
- A deterministic hardware FSM clamps shared buses, flushes internal bank pipeline registers, and emits a single-cycle `bank_role_clear` strobe before granting ownership to the incoming tenant.

### 2.6 Hardware Auto-Gating Lifetime Countdown
- PEs integrate an 8-bit lifetime counter (`LIFETIME_W = 8`), allowing precise programming of execution windows up to 255 cycles.
- When a tenant finishes its allocated computation window, its region automatically clock-gates, reducing dynamic switching power to zero while the co-tenant continues.

---

## 3. The Three Architectural Exploration Models

To benchmark each contribution systematically, this repository provides three self-contained models:

| Model Directory | Architectural Configuration | Multi-Tenancy | Per-Region Dataflow | Key Workload Fit |
| :--- | :--- | :---: | :---: | :--- |
| [**models/pipelined/dataflow_switching/**](models/pipelined/dataflow_switching) | **Configuration B** (ReDas Baseline) | Single Tenant Only | Global WS / OS / IS | Single-model sequential layer execution |
| [**models/pipelined/spatial_fission/**](models/pipelined/spatial_fission) | **Configuration A** (Planaria Baseline) | Multi-Tenant (Region A + B) | Rigidly Locked to WS | Concurrent CNN workloads |
| [**models/pipelined/heterogeneous_fission/**](models/pipelined/heterogeneous_fission) | **Configuration C** (Novel Proposed Idea) | **Multi-Tenant (Region A + B)** | **Independent Runtime WS / OS / IS** | **Simultaneous CNN (WS) + Transformer (OS) co-execution** |

*(Non-pipelined combinational MAC baselines are likewise provided in [models/non_pipelined/](models/non_pipelined/) for timing and area reference.)*

---

## 4. Scalable Systolic Array Exploration (4x4, 8x8, 16x16)

All three models feature standalone top wrappers and testbenches across three array scales, enabling exploration of compute density, interconnect timing, and memory traffic:

| Array Dimensions | Processing Elements | Flip-Flop Count (PE Array) | Memory Banks | Column Split Width (`SPLIT_W`) | Drain Window (`LIFETIME_W`) | Peak INT8 Throughput (@ 200 MHz) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **4x4** (Baseline) | 16 PEs | 1,504 flops | 2 Banks | 4 bits (`[3:0]`) | 8 bits (up to 255 cyc) | 6.40 GOPS |
| **8x8** (Scaled Pod) | 64 PEs | 6,016 flops | 2 Banks | 4 bits (`[3:0]`) | 8 bits (up to 255 cyc) | 25.60 GOPS |
| **16x16** (Full Pod) | 256 PEs | 24,064 flops | 4 Banks | 5 bits (`[4:0]`) | 8 bits (up to 255 cyc) | 102.40 GOPS |

### Key Architectural Upgrades for Scaled Arrays:
1. **Parameterized Fission Decoder:** `SPLIT_W` dynamically scales as `($clog2(NUM_COLS + 1) >= 4) ? $clog2(NUM_COLS + 1) : 4`, allowing up to 16 columns (17 split states) without bit overflow.
2. **Scalable Multi-Bank Clear Routing:** Dynamic `region_bank_clear` logic routes bank completion pulses to region owners across arbitrary bank counts (2, 4, 8) using `bank_owner_bus`.
3. **Column 0 Boundary Multiplexing:** Correctly routes `din_w_region_b` even during extreme partitions where `cfg_split_col = 0` (entire array allocated to Region B).
4. **Dedicated Scaled Top Wrappers:** Standalone top wrappers (`dfs_top_8x8`, `dfs_top_16x16`, `sfa_top_8x8`, `sfa_top_16x16`, `hdf_top_8x8`, `hdf_top_16x16`) allow direct elaboration in Cadence Genus and Innovus.

---

## 5. Real-Workload Multi-Tenant Benchmarking & Accuracy Co-Verification

The [`benchmarks/`](benchmarks/) suite executes real, pretrained neural network workloads directly on the synthesized RTL across all three models and all three array scales:
- **Tenant A:** ResNet-50 Convolutional Layer (`res4a_branch2b`), optimal in **Weight-Stationary (WS)** mode.
- **Tenant B:** Vision Transformer (ViT-Base) Self-Attention ($Q \cdot K^T$), optimal in **Output-Stationary (OS)** mode.
- **Data Precision:** Quantized signed INT8 $\times$ INT8 with 32-bit accumulation (`INT32`).

### 5.1 Multi-Scale Empirical Throughput Comparison

| Scale | Metric | Model 1: Sequential (ReDas) | Model 2: Homog. Fission (Planaria) | Model 3: PolyFlow-NPU (Proposed) | PolyFlow Win vs. Baselines |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **4x4** (16 PEs) | **Makespan (cycles)** | 54 cyc | 58 cyc | **28 cyc** | **1.93× vs M1** / **2.07× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.27 $\mu\text{s}$ | 0.29 $\mu\text{s}$ | **0.14 $\mu\text{s}$** | **48.1% Latency Reduction** |
| | **Sustained Throughput** | 1.90 GOPS | 1.77 GOPS | **3.66 GOPS** | **Peak: 6.40 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 29.6% | 27.6% | **57.1%** | **+29.6% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.48× | 1.45× | **2.00×** | **Optimal 2.00× parallel scaling bound** |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **8x8** (64 PEs) | **Makespan (cycles)** | 100 cyc | 106 cyc | **52 cyc** | **1.92× vs M1** / **2.04× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.50 $\mu\text{s}$ | 0.53 $\mu\text{s}$ | **0.26 $\mu\text{s}$** | **48.0% Latency Reduction** |
| | **Sustained Throughput** | 8.19 GOPS | 7.73 GOPS | **15.75 GOPS** | **Peak: 25.60 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 32.0% | 30.2% | **61.5%** | **+31.3% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.48× | 1.45× | **2.00×** | **Optimal 2.00× parallel scaling bound** |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **16x16** (256 PEs) | **Makespan (cycles)** | 192 cyc | 202 cyc | **100 cyc** | **1.92× vs M1** / **2.02× vs M2** |
| | **Execution Time (@ 200 MHz)** | 0.96 $\mu\text{s}$ | 1.01 $\mu\text{s}$ | **0.50 $\mu\text{s}$** | **47.9% Latency Reduction** |
| | **Sustained Throughput** | 34.13 GOPS | 32.44 GOPS | **65.54 GOPS** | **Peak: 102.40 GOPS** |
| | **PE Compute Utilization ($U_{\text{PE}}$)** | 33.3% | 31.7% | **64.0%** | **+32.3% Utilization Gain** |
| | **Multi-Tenant Weighted Speedup ($WS$)** | 1.48× | 1.46× | **2.00×** | **Optimal 2.00× parallel scaling bound** |

### 5.2 100% Bit-Exact Numerical Co-Verification
Every hardware accumulator dump is verified against pure Python NumPy INT32 mathematical ground truth ([`verify_accuracy.py`](benchmarks/scripts/verify_accuracy.py)):
- **Match Rate:** **100.00%** across all 18 output matrices (6 per scale $\times$ 3 scales).
- **Mean Squared Error (MSE):** **0.000000**
- **Cosine Similarity:** **1.000000**

---

## 6. Repository Directory Structure & Scale Partitioning

All simulation outputs, logic synthesis reports, gate-level netlists, and physical design deliverables are strictly partitioned into scale-specific directories (`4x4/`, `8x8/`, `16x16/`):

```
mt_npu/
├── benchmarks/                           # Automated real-workload throughput & accuracy suite
│   ├── data/{4x4,8x8,16x16}/             # Real quantized INT8 weights & golden models
│   ├── tb/                               # Cycle-accurate cosimulation testbenches (M1, M2, M3)
│   ├── scripts/                          # Workload generator, benchmark runner, and verifier
│   └── results/{4x4,8x8,16x16}/          # Hardware traces, metrics JSON, throughput_summary.md
│
├── figures/                              # Publication-grade architectural diagrams (PNG)
│   ├── polyflow_arch.png                 # Master PolyFlow-NPU microarchitecture diagram
│   ├── fig0_comparison.png               # Side-by-side taxonomy and comparative matrix
│   ├── figA_homo_fission.png             # Configuration A: Homogeneous Fission Pod
│   ├── figB_seq_switch.png               # Configuration B: Sequential Dataflow Switching Pod
│   └── figC_hetero_fission.png           # Configuration C: Heterogeneous Fission Pod
│
├── models/                               # Architectural exploration models
│   ├── common.mk                         # Unified scaling-aware make rules
│   │
│   ├── pipelined/                        # [Pipelined Models] Two-Stage MAC + Carry-Save Accumulator
│   │   ├── dataflow_switching/           # Model 1: Single-tenant runtime WS/OS/IS switching
│   │   ├── spatial_fission/              # Model 2: Homogeneous spatial multi-tenancy
│   │   └── heterogeneous_fission/        # Model 3: Heterogeneous Fission (PolyFlow-NPU)
│   │       ├── rtl/                      # Parameterized RTL + standalone 8x8 & 16x16 wrappers
│   │       ├── tb/                       # Scale-specific testbenches (4x4, 8x8, 16x16)
│   │       ├── reports/{4x4,8x8,16x16}/  # Partitioned Genus synthesis & Innovus reports
│   │       ├── netlist/{4x4,8x8,16x16}/  # Gate-level netlists (.v), SDC, SDF
│   │       ├── output/{4x4,8x8,16x16}/   # Simulation executables & waveforms
│   │       ├── outputs/{4x4,8x8,16x16}/  # Innovus postroute DEF, netlist, SDF deliverables
│   │       ├── db/{4x4,8x8,16x16}/       # Innovus design database checkpoints (.enc)
│   │       ├── synth_hdf.tcl             # Multi-scale Cadence Genus synthesis script
│   │       ├── pnr_place_hdf.tcl         # Multi-scale Cadence Innovus PnR script
│   │       └── Makefile                  # Model Makefile
│   │
│   └── non_pipelined/                    # [Non-Pipelined Models] Single-cycle combinational MAC
│       ├── dataflow_switching/
│       ├── spatial_fission/
│       └── heterogeneous_fission/
│
├── scripts/
│   ├── run_all_models.sh                 # Unified regression runner (supports 4x4, 8x8, 16x16, all)
│   ├── innovus_self_adapting.tcl         # Self-adapting Cadence Innovus PnR script
│   ├── cts.tcl                           # Clock Tree Synthesis (CCOpt) configuration
│   └── viewDefinition.tcl                # MMMC timing analysis view definitions
│
├── Makefile                              # Top-level master automation Makefile
├── .gitignore                            # Excludes build sandboxes while tracking deliverables
└── README.md                             # Global repository documentation (this file)
```

---

## 7. Verification and Simulation Guide

### 7.1 Fast Multi-Size Verification (Icarus Verilog)
Run cycle-accurate SystemVerilog unit testbenches verifying **100% of all PEs** ($16/16$, $64/64$, $256/256$) across WS, OS, and IS modes:

```bash
# Verify ALL 3 models across ALL 3 array sizes (4x4, 8x8, 16x16 -- 9 testsuites):
make test-scaling-all

# Or verify a specific array size across all 3 models:
make test-4x4-all           # All models at 4x4 (16 PEs each) -> output in output/4x4/
make test-8x8-all           # All models at 8x8 (64 PEs each) -> output in output/8x8/
make test-16x16-all         # All models at 16x16 (256 PEs each) -> output in output/16x16/

# Or verify individual models across all sizes:
make test-scaling-model1    # Dataflow Switching (4x4, 8x8, 16x16)
make test-scaling-model2    # Spatial Fission (4x4, 8x8, 16x16)
make test-scaling-model3    # Heterogeneous Fission (4x4, 8x8, 16x16)
```

### 7.2 Real-Workload Throughput Benchmarks
```bash
# Run full benchmark across all 3 models and 3 scales (4x4, 8x8, 16x16):
make benchmark

# Run individual scales:
make benchmark-4x4
make benchmark-8x8
make benchmark-16x16

# Verify 100% bit-exact numerical accuracy:
make benchmark-verify
```

### 7.3 Strict Verilator Linting
```bash
# Strict -Wall linting without waivers across all pipelined and non-pipelined models:
make lint
```

### 7.4 Cadence Xcelium Simulation
```bash
# Headless batch mode:
make run-model1 SCALE=4x4
make run-model2 SCALE=8x8
make run-model3 SCALE=16x16
make run-all    SCALE=4x4

# Interactive SimVision GUI mode:
make gui-model3
```

---

## 8. Cadence Digital ASIC Implementation Flow (90nm)

The designs are synthesized and placed-and-routed using **Cadence Genus Synthesis Solution** and **Cadence Innovus Implementation System** targeting a 90nm bulk CMOS standard-cell library (`slow.lib` / `fast.lib` MMMC corners):

### 8.1 Multi-Scale Logic Synthesis (Cadence Genus)
Reports land cleanly inside `reports/${SCALE}/` and gate-level netlists in `netlist/${SCALE}/`:

```bash
# Synthesize all models for a specific scale:
make synth-4x4-all          # 4x4 baseline synthesis across all 3 models
make synth-8x8-all          # 8x8 scaled pod synthesis across all 3 models
make synth-16x16-all        # 16x16 full pod synthesis across all 3 models
make synth-scaling-all      # Synthesize all models across 4x4, 8x8, and 16x16

# Or synthesize individual models:
make synth-model1 SCALE=4x4
make synth-model2 SCALE=8x8
make synth-model3 SCALE=16x16
```

- **Timing Constraints:** Target clock period $T_{\text{clk}} = 5.000\text{ ns}$ (200 MHz), clock uncertainty 0.050 ns, input/output delay 0.500 ns.
- **Reports Generated:** `timing_*.rpt`, `power_*.rpt`, `area_*.rpt`, `qor_*.rpt`, `gates_*.rpt`.

### 8.2 Multi-Scale Physical Design: Place-and-Route (Cadence Innovus)
PnR deliverables land in `outputs/${SCALE}/`, database checkpoints in `db/${SCALE}/`, and CTS reports in `reports/${SCALE}/cts/`:

```bash
# Run Innovus placement & routing across all models for a specific scale:
make pnr-place-4x4-all      # 4x4 PnR across all 3 models
make pnr-place-8x8-all      # 8x8 PnR across all 3 models
make pnr-place-16x16-all    # 16x16 PnR across all 3 models
make pnr-place-scaling-all  # PnR across all scales and all models

# Or run Innovus on individual models:
make pnr-place-model1 SCALE=4x4
make pnr-place-model2 SCALE=8x8
make pnr-place-model3 SCALE=16x16
```

- **Technology and Metal Stack:** Standard 90nm 7-metal grid (`metal1` to `metal7`), `gsclib090site` core site.
- **Clock Tree Synthesis (CCOpt):** Balanced clock DAG with non-default routing rules (`2w2s`), zero clock gating violations, and target insertion delay < 0.65 ns.
- **Post-Route Deliverables:** Placed & routed DEF (`outputs/${SCALE}/*_postroute.def`), signoff netlists (`*_postroute.v`), SDF files (`*_postroute.sdf`), DRC (`*_postroute_drc.rpt`), and connectivity reports.
- **Timing Closure:** Achieves **+1.200 ns positive setup slack** ($f_{\text{max}} \approx 263.2\text{ MHz}$) at 200 MHz due to the two-stage pipelined datapath and carry-save accumulator.
