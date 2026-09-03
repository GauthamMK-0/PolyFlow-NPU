# Architecture Specification: Homogeneous Spatial Fission Model (Model 2)

> **Intuitive Summary:**
> Think of this model like dividing a large highway into two separate, physical lanes with a median wall down the middle. Two different cars can drive at the same time without hitting each other. However, **both cars are forced to drive at the exact same gear and speed (Weight-Stationary only)**.

---

## 1. Core Idea & The Problem It Solves

In Model 1, when two separate AI models need to run (e.g., an object detector and a speech recognizer in a smart vehicle), they must wait in line. While one model occupies the array, the other waits. If either model is small, most of the chip's PEs sit completely idle.

**The Model 2 Solution:**
Model 2 introduces **Spatial Fission** (following the architecture of prior research such as MICRO'20 *Planaria*):
- The physical $M \times N$ systolic array is dynamically sliced into **independent sub-arrays (Region A and Region B)** at runtime.
- Region A can compute Model 1, while Region B simultaneously computes Model 2 on the exact same clock cycle.
- **The Constraint:** Both Region A and Region B are **rigidly locked to Weight-Stationary (WS)** dataflow. There is no per-region dataflow switching.

---

## 2. Dynamic Column Slicing & Boundary Isolation

### 2.1 The Fission Decoder (`sfa_fission_decoder.v`)
At dispatch time, the host controller sends a split column index `cfg_split_col` (e.g., `4'd2` on a 4-column array):
- Columns $c < 2$ (Cols 0 and 1) are marked as **Region A** (`region_id_mask = 0`).
- Columns $c \ge 2$ (Cols 2 and 3) are marked as **Region B** (`region_id_mask = 1`).

```
           Physical Array Sliced at Column 2
           
       [ Region A ]            [ Region B ]
      Col 0    Col 1          Col 2    Col 3
     +------+ +------+  ||   +------+ +------+
     |  PE  | |  PE  |  ||   |  PE  | |  PE  |
     +------+ +------+  ||   +------+ +------+
                        ||
                 Active Barrier
               (Cross-Wires Zeroed)
```

### 2.2 Hardware Boundary Isolation (`sfa_array.v`)
In a normal systolic array, PE outputs pass combinationally from left to right. If left untreated, activations from Region A would leak right into Region B and corrupt its calculations.

To prevent this, the boundary PE at column `cfg_split_col` severs the connection from the left and routes to a dedicated input pin (`din_w_region_b`):
$$\text{Input to Col } c = \begin{cases} \text{din\_w\_region\_b} & \text{if crossing the boundary} \\ \text{mesh output from left} & \text{otherwise} \end{cases}$$
This provides **electrical isolation**: Region A and Region B run completely independently with **zero cross-talk**.

---

## 3. Shared Memory Subsystem & Multi-Tenant Safety

When multiple tenants share an accelerator chip, they share the on-chip memory banks. Model 2 includes three dedicated hardware safety engines:

### 3.1 EPPA Bandwidth Arbiter (`sfa_eppa.v`)
To avoid memory bandwidth contention, the Event-Driven Phase-Pinned Arbiter monitors execution phases:
- `PH_BURST` (`2'b00`): Region is preloading weights $\to$ gets **100% memory bandwidth (`0xFF`)**.
- `PH_STREAM` (`2'b10`): Region is streaming activations $\to$ gets **50% balanced bandwidth (`0x7F`)**.
- `PH_IDLE` (`2'b01`): Region is waiting $\to$ gets **0% bandwidth (`0x00`)**.
Bandwidth is updated only during phase transitions and stays pinned during compute, keeping the clock path fast.

### 3.2 OTP Token Protocol (`sfa_otp_fsm.v`)
To prevent two regions from modifying the same memory bank simultaneously, banks use a Single-Writer Ownership Token. A rotating epoch counter rotates priority between Region A and Region B so neither tenant is ever starved.

### 3.3 Mandatory 4-Cycle Bank Scrubbing (`sfa_bank_scrub.v`)
When a memory bank is transferred from Region A to Region B, there is a risk that Region B could read residual sensitive weights from Region A (a data retention security attack).
- The hardware enforces a **mandatory 4-cycle zeroing scrub**.
- The bank is actively overwritten with zeroes before `bank_role_clear` is signaled to Region B.

---

## 4. Cycle-by-Cycle Worked Example

In our testbench, a 4-column array is split symmetrically at column 2:
1. **Partition Step (Cycle 0):** `cfg_split_col = 2`. Mask becomes `1100` (Cols 0–1 = Reg A, Cols 2–3 = Reg B).
2. **Preload Step (Cycle 1):** Both regions preload stationary weights at the same time:
   - Region A preloads weight $W_A = 5$.
   - Region B preloads weight $W_B = 7$.
3. **Concurrent Compute (Cycles 2–5):** Both regions stream activations simultaneously:
   - Region A streams activation $X_A = 3$ into columns 0–1.
   - Region B streams activation $X_B = 2$ into columns 2–3.
   - Accumulator equations over 4 cycles:
     $$\text{Region A PE[0][0]} = 4 \times (5 \times 3) = 60$$
     $$\text{Region B PE[0][2]} = 4 \times (7 \times 2) = 56$$
   - Both results complete on the exact same clock cycle without interfering with each other.

---

## 5. Architectural Trade-offs & Limitations

| Advantage | Limitation |
|---|---|
| **Eliminates Queue Stalls:** Two models run concurrently, cutting latency for multi-tenant serving. | **Dataflow Inflexibility:** All regions must run Weight-Stationary. If Region B runs a Transformer Self-Attention, it wastes massive memory power. |
| **High Hardware Efficiency:** Hardware boundary barrier prevents data corruption with minimal silicon overhead. | **Substrate Rigidity:** Cannot adapt per-region dataflow to match diverse multi-modal AI workloads. |

This limitation directly motivates our **Novel Heterogeneous Fission Model (Model 3)**.
