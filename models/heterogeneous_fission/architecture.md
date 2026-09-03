# Architecture Specification: Novel Heterogeneous Fission Model (Model 3)

> **Intuitive Summary:**
> Think of this model like an advanced dual-lane highway where two vehicles travel side-by-side. Not only are the lanes safely divided by a crash barrier, but **each lane allows a completely different type of vehicle optimized for its own mission**: Lane 1 carries a heavy cargo truck in 4th gear (a CNN in Weight-Stationary mode), while Lane 2 carries a high-speed electric car (Transformer Attention in Output-Stationary mode). They share the roadway with zero traffic jams and zero collisions.

---

## 1. The Novel Idea: Composing Two Worlds

Prior accelerators forced a painful trade-off:
- **Model 1 (Dataflow Switching):** Can switch between WS, OS, and IS, but **only for one tenant at a time**. Multi-model systems suffer severe queue delays.
- **Model 2 (Spatial Fission):** Can run multiple tenants concurrently, but **all tenants are locked to Weight-Stationary**. Running a modern Transformer Attention layer on WS wastes enormous energy.

**Our Proposed Novelty (DRDS-NPU / HDF-NPU):**
Model 3 composed both ideas for the first time:
$$\textbf{Heterogeneous Fission} = \textbf{Spatial Fission} + \textbf{Independent Per-Region Dataflow Selection}$$

Each partitioned region independently chooses its optimal dataflow at runtime:
- **Region A:** Executes a CNN backbone (ResNet/ConvNeXt) in **Weight-Stationary (WS)** mode.
- **Region B:** Simultaneously executes Transformer Self-Attention ($Q \cdot K^T$) in **Output-Stationary (OS)** mode on the exact same clock cycles!

---

## 2. Deep-Dive Hardware Architecture

```
                                [Host Multi-Tenant Scheduler]
                                              |
                                              v
                              [Dynamic Fission Decoder]
                                      /        \
                   (cfg_split_col=2) /          \ (modes: Reg A=WS, Reg B=OS)
                                    v            v
             +---------------------------+  ||  +---------------------------+
             |   Region A (Cols 0-1)     |  ||  |   Region B (Cols 2-3)     |
             |   Mode: Weight-Stationary |  ||  |   Mode: Output-Stationary |
             |   Workload: CNN Conv      |  ||  |   Workload: Attention     |
             +---------------------------+  ||  +---------------------------+
                                            ||
                                      Active Barrier
                                    (Zeroing Isolation)
                                            |
                         +------------------+------------------+
                         |     Shared On-Chip Memory Subsystem  |
                         |  [EPPA Arbiter]  [OTP Token] [Scrub]|
                         +-------------------------------------+
```

### 2.1 The Heterogeneous Processing Element (`hdf_pe.v`)
Each PE in Model 3 combines:
1. **3-Dataflow Multiplexers:** Switches between WS (`mul_a = stat_reg, mul_b = din_w`), OS (`mul_a = din_n, mul_b = din_w`), and IS (`mul_a = stat_reg, mul_b = din_w`) based on the region's dynamic mode.
2. **In-Flight Lifetime Countdown Register (`lifetime_cnt`):** When regions shift boundaries, in-flight calculations must gracefully drain before new workloads enter. The lifetime counter decrements to 0 and cleanly gates the multiplier.
3. **Bank Role Stale Flag (`bank_role_stale`):** Prevents PEs from reading un-scrubbed memory banks until the hardware scrub cycle finishes.

### 2.2 2D Mesh with Dynamic Boundary Barrier (`hdf_array_grid.v`)
- Slices the physical grid at `cfg_split_col`.
- Cross-region horizontal wires are zeroed so activations from Region A can never bleed into Region B.
- Region B receives fresh operands directly via dedicated west input pins (`din_w_region_b`).

### 2.3 EPPA Dynamic Memory Bandwidth Balancing (`eppa_arbiter.v`)
Because Region A and Region B run different dataflows, their memory access profiles are complementary:
- Region A (WS) preloads weights, then enters steady compute (memory idle).
- Region B (OS) continuously streams queries ($Q$) and keys ($K$) from memory.
- **The EPPA Advantage:** As soon as Region A transitions to compute, EPPA automatically shifts idle memory bandwidth to Region B, eliminating memory bottlenecks without complex clock arbitration!

### 2.4 OTP Token & Mandatory 4-Cycle Zeroing Scrub (`otp_token_fsm.v`, `pod_bank_scrub.v`)
- Decentralized single-writer ownership guarantees race-free memory allocation.
- When a bank migrates between tenants, a 4-cycle hardware zeroing scrub clears all residual data, provably stopping tenant snooping and data-retention side channels.

---

## 3. Concrete Cycle-by-Cycle Co-Execution Example

Here is the exact cycle trace from our verified testbench:

| Cycle | Region A Action (Mode: WS, Conv) | Region B Action (Mode: OS, Attention) | Hardware Status |
|:---:|---|---|---|
| **0** | Split at Col 2. Mode set to WS (`00`). Clear acc. | Split at Col 2. Mode set to OS (`01`). Clear acc. | Boundary barrier active at Col 2 |
| **1** | Preload weight $W_A = 5$. Set lifetime = 15. | Set lifetime = 15. Accumulator ready. | EPPA: Region A in BURST (0xFF BW) |
| **2** | Stream activation $X_A = 3$. <br/>`acc_A = 0 + (5 * 3) = 15` | Stream $Q = 4$ (North) and $K = 7$ (West). <br/>`acc_B = 0 + (4 * 7) = 28` | Both regions compute simultaneously! |
| **3** | Stream activation $X_A = 3$. <br/>`acc_A = 15 + 15 = 30` | Stream $Q = 2$ (North) and $K = 6$ (West). <br/>`acc_B = 28 + (2 * 6) = 40` | Zero cross-talk across boundary |
| **4** | Stream activation $X_A = 3$. <br/>`acc_A = 30 + 15 = 45` | Attention tile complete. Acc holds score `40`. | EPPA shifts memory BW to Region B |
| **5** | Stream activation $X_A = 3$. <br/>`acc_A = 45 + 15 = 60` | Standby / Result drain. | Region A final result = `60` |

Both calculations finish with 100% mathematical precision on the exact same clock cycles.

---

## 4. Architectural Comparison Across All Three Models

| Feature | Model 1 (Dataflow Switching) | Model 2 (Spatial Fission) | Model 3 (Novel Heterogeneous Fission) |
|---|:---:|:---:|:---:|
| **Multi-Tenancy** | Single Tenant Only | Multi-Tenant | **Multi-Tenant** |
| **Per-Region Dataflow** | Uniform Full-Array | Locked to Weight-Stationary | **Independent Runtime Choice (WS/OS/IS)** |
| **Workload Co-Execution** | None (Queued Serial) | Homogeneous Only (WS + WS) | **Heterogeneous (CNN WS + Attention OS)** |
| **Boundary Isolation** | None (Unsplit) | Static Boundary | **Dynamic Hardware Barrier Zeroing** |
| **Memory Bandwidth** | Static Single Bus | Phase-Driven (EPPA) | **Dynamic Phase Balancing (EPPA)** |
| **Hardware Scrubbing** | None | 4-Cycle Zeroing | **4-Cycle Zeroing + Stale Handshake** |
| **In-Flight Safety** | Drain on Finish | Abrupt Flush | **Hardware Lifetime Countdown** |
