# Architecture Specification: Homogeneous Spatial Fission Architecture (Model 2)

## 1. Executive Summary & Design Scope

The **Spatial Fission Model** represents a multi-tenant accelerator that dynamically partitions a single physical 2D systolic array into multiple isolated execution regions (e.g., Region A and Region B). This architecture corresponds to **Configuration A** in the evaluation framework (and follows the design philosophy of state-of-the-art spatial partitioning accelerators such as MICRO'20 *Planaria*).

### Fundamental Architectural Trade-off
- **Spatial Multi-Tenancy:** Enabled. Distinct inference tasks run concurrently on disjoint column slices of the physical mesh, eliminating Head-of-Line (HoL) queue stalls and maximizing utilization on small-to-medium batch sizes.
- **Dataflow Homogeneity:** All partitioned regions are **rigidly locked to Weight-Stationary (WS)** dataflow. PEs lack runtime dataflow selection multiplexers.

---

## 2. Dynamic Column Partitioning & Boundary Isolation

### 2.1 Fission Decoder (`sfa_fission_decoder.v`)
At dispatch time, the host controller writes a split column index `cfg_split_col` and pulses `cfg_update_strobe`. The decoder generates:
1. `region_id_mask[c]`: High for columns assigned to Region B ($c \ge \text{cfg\_split\_col}$), Low for Region A ($c < \text{cfg\_split\_col}$).
2. `region_reassign_bus[c]`: 1-cycle strobe indicating which columns have crossed region ownership boundaries.

```
       Array Boundary (cfg_split_col = 2)
              |
   Region A   |   Region B
 [Col 0][Col 1] [Col 2][Col 3]
       ======>|  (Inter-region isolation: wires zeroed)
              |
              +--> Direct feed from din_w_region_b
```

### 2.2 Hardware Boundary Isolation (`sfa_array.v`)
To ensure zero inter-tenant data bleeding, horizontal systolic connections (`mesh_w`) crossing a region boundary are electrically isolated:
$$\text{mesh\_w}[r][c] = (\text{region\_id\_mask}[c] \ne \text{region\_id\_mask}[c-1]) \ ?\ \text{din\_w\_region\_b}[r] : \text{mesh\_e}[r][c-1]$$
- PEs in Region A receive their West inputs from external pins (`din_w`) and forward eastwards.
- Column $c = \text{cfg\_split\_col}$ isolates Region B from Region A by multiplexing directly to `din_w_region_b`, completely cutting off residual signals from Region A.

---

## 3. Memory Subsystem & Co-Tenant Security

Multi-tenancy introduces shared memory contention and potential information leakage. Model 2 incorporates three dedicated hardware controllers to guarantee fair bandwidth allocation and provable spatial isolation:

### 3.1 Event-Driven Phase-Pinned Arbiter (EPPA, `sfa_eppa.v`)
Instead of performing complex round-robin arbitration on every 1 GHz clock cycle, EPPA monitors coarse-grained execution phases (`phase_tag`):
- `PH_BURST` (`2'b00`): Weight preload phase $\rightarrow$ Allocates maximum memory bandwidth (`0xFF`).
- `PH_STREAM` (`2'b10`): Steady-state streaming compute $\rightarrow$ Allocates balanced bandwidth (`0x7F`).
- `PH_IDLE` (`2'b01`): Execution finished or waiting $\rightarrow$ Zero bandwidth allocation (`0x00`).
- `PH_RECONFIG` (`2'b11`): Transition phase $\rightarrow$ Asserts `reconfig_urgent` strobe.

Bandwidth is pinned quasi-statically during steady-state, eliminating clock-frequency bottlenecks.

### 3.2 Ownership Token Protocol (OTP, `sfa_otp_fsm.v`)
Shared memory banks use a single-writer ownership protocol. A region must acquire the bank's token before writing or reconfiguring it. To prevent starvation, an epoch counter periodically increments `priority_base`, rotating grant priority among regions.

### 3.3 Mandatory Hardware Bank Scrubbing (`sfa_bank_scrub.v`)
When a memory bank is transferred from Region A to Region B:
1. `role_reassign` triggers `scrub_active = 1'b1`.
2. The controller executes a **4-cycle mandatory zeroing sequence**, actively clearing residual weight/activation data left by the previous tenant.
3. Only after the 4th cycle does `bank_role_clear` pulse, un-gating PEs in the new region.
4. This provably thwarts data retention and side-channel cross-tenant sniffing attacks.

---

## 4. Architectural Limitations of Homogeneous Fission

While Model 2 successfully enables concurrent spatial multi-tenancy:
1. **Dataflow Mismatch:** Locking all regions to Weight-Stationary forces Transformer Attention tiles ($Q \cdot K^T$) to execute sub-optimally, generating $3\times$ to $5\times$ higher SRAM writeback energy compared to Output-Stationary.
2. **Substrate Inflexibility:** Workload diversity in modern AI models requires heterogeneous dataflow freedom *within* spatial partitions.
