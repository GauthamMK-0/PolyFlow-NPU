# Architecture Specification: Novel Heterogeneous Fission Architecture (Model 3)

## 1. Executive Summary & Novel Contributions

The **Heterogeneous Fission Model** (DRDS-NPU / HDF-NPU) is our proposed novel architecture, representing **Configuration C** in the evaluation framework. It resolves the fundamental trade-off present in prior accelerators by unifying two previously mutually exclusive capabilities:

1. **Concurrent Spatial Multi-Tenancy (Fission):** A physical 2D systolic array dynamically divides into independent execution regions at runtime.
2. **Independent Per-Region Dataflow Freedom:** Unlike homogeneous spatial accelerators (e.g., Planaria) where all regions are locked to Weight-Stationary, each partitioned region in DRDS-NPU independently executes in **Weight-Stationary (WS)**, **Output-Stationary (OS)**, or **Input-Stationary (IS)** mode.

### The Concrete Multi-Tenant Payoff
Consider an autonomous robotics edge pod running:
- **Tenant 1 (Perception Backbone):** ResNet-50 / ConvNeXt convolutional layers $\rightarrow$ Optimal on **Weight-Stationary (WS)**.
- **Tenant 2 (Planner / NLP):** Transformer Multi-Head Self-Attention ($Q \cdot K^T$) $\rightarrow$ Optimal on **Output-Stationary (OS)**.

In DRDS-NPU, Region A executes ResNet in WS mode, while Region B *simultaneously* executes Self-Attention in OS mode on the exact same clock cycles, with hardware boundary isolation, dynamic memory bandwidth balancing (EPPA), and anti-leakage memory bank scrubbing.

---

## 2. Heterogeneous Processing Element (`hdf_pe.v`)

The core compute engine of Model 3 unifies 3-dataflow multiplexing with spatial handover handshakes:

```
                            [din_n (North)]
                                  |
                                  v
                       +----------------------+
                       |   hdf_pe Datapath    |
                       |                      |
      [din_w (West)] --+-> [ MUX_A ]  [ MUX_B ] <- [din_n / stat_reg]
                       |        \        /    |
                       |      [ Multiplier ]  |
                       |            |         |
                       |      [ 32-bit Acc ]  |
                       |            |         |
                       |  [ Lifetime Counter] |
                       |  [ Stale Handshake ] |
                       +------------+---------+
                                    |
                        [dout_s]    |    [dout_e]
```

### Key Sub-Blocks Inside Each PE:
1. **3-Way Dataflow Multiplexer:** Driven by `dataflow_mode[reg_id*2 +: 2]`:
   - `2'b00` (WS): `mul_a = stat_operand_reg`, `mul_b = din_w`
   - `2'b01` (OS): `mul_a = din_n`, `mul_b = din_w`
   - `2'b10` (IS): `mul_a = stat_operand_reg`, `mul_b = din_w`
2. **Lifetime Drain Counter (`lifetime_cnt`):**
   When spatial partitioning shifts or a region finishes execution, in-flight partial sums must drain without corrupting incoming workloads. The lifetime counter decrements to 0; computation is strictly gated when `lifetime_cnt == 0`.
3. **Bank Role Stale Flag (`bank_role_stale`):**
   Asserted automatically on `region_reassign`. Gated from executing MAC operations until the memory bank has completed its 4-cycle hardware scrub sequence (`bank_role_clear`).

---

## 3. 2D Mesh with Dynamic Boundary Isolation (`hdf_array_grid.v`)

The systolic mesh supports runtime column splitting:
- Columns $c < \text{cfg\_split\_col}$ belong to Region A.
- Columns $c \ge \text{cfg\_split\_col}$ belong to Region B.

### Dynamic Horizontal Boundary Wire Isolation:
$$\text{mesh\_w}[r][c] = (\text{region\_id\_mask}[c] \ne \text{region\_id\_mask}[c-1]) \ ?\ \text{din\_w\_region\_b}[r] : \text{mesh\_e}[r][c-1]$$
- Cross-region wires are electrically severed and routed to Region B's dedicated boundary input pins (`din_w_region_b`).
- Independent `dataflow_mode`, `lifetime_ld`, `w_ld`, and `acc_clr` signals are dispatched to each PE column based on its region assignment.

---

## 4. Shared Dynamic Memory Subsystem

Multi-tenant co-execution on shared on-chip memory banks requires strict bandwidth fairness and mutual exclusion:

| Subsystem | RTL Module | Architectural Function |
|---|---|---|
| **EPPA Arbiter** | `eppa_arbiter.v` | Event-driven phase-pinned memory bandwidth arbiter. Monitors `PH_BURST`, `PH_STREAM`, `PH_IDLE`, and `PH_RECONFIG`. Pins bandwidth during steady-state to eliminate clock critical path overhead. |
| **OTP Token FSM** | `otp_token_fsm.v` | Single-writer ownership token protocol with rotating epoch counter priority. Guarantees race-free bank re-allocation without thread starvation. |
| **Pod Bank Scrub** | `pod_bank_scrub.v` | 4-cycle active zeroing scrub engine. Clears all residual tenant weights/activations before releasing bank clear strobe (`bank_role_clear`). |

---

## 5. Architectural Comparison Matrix

| Architectural Feature | Model 1: Dataflow Switching | Model 2: Spatial Fission | Model 3: Heterogeneous Fission (Ours) |
|---|:---:|:---:|:---:|
| **Spatial Multi-Tenancy** | Single Tenant | Concurrent Multi-Tenant | **Concurrent Multi-Tenant** |
| **Region A Dataflow** | WS / OS / IS (Time-multiplexed) | Rigid WS | **Runtime WS / OS / IS** |
| **Region B Dataflow** | N/A (Full Array Single Tenant) | Rigid WS | **Runtime WS / OS / IS** |
| **Co-Execution Capability** | None (Queued HoL) | Homogeneous Only | **Heterogeneous (CNN + Attention)** |
| **Boundary Isolation** | None | Static Column Mux | **Dynamic Boundary Zeroing** |
| **Memory Bandwidth Arbiter** | Static Bus | Coarse Phase (EPPA) | **Coarse Phase (EPPA)** |
| **Anti-Leakage Bank Scrubbing** | None | 4-cycle Scrub | **4-cycle Scrub + Stale Handshake** |
| **Partial Sum In-Flight Safety** | Drain on Finish | Abrupt Flush | **Hardware Lifetime Countdown** |
