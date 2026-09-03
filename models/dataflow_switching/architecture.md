# Architecture Specification: Dataflow Switching Architecture (Model 1)

## 1. Executive Summary & Design Scope

The **Dataflow Switching Model** represents a single-tenant spatial accelerator capable of reconfiguring its computation dataflow at tile boundaries. In conventional deep learning accelerators (e.g., Google TPU v1), the processing element (PE) array is hardwired to a single dataflow—predominantly **Weight-Stationary (WS)**. While WS achieves near-optimal energy efficiency for convolutional layers where weights can be reused across a large 2D activation grid, it exhibits severe utilization degradation and memory traffic overhead on modern transformer layers such as Self-Attention ($Q \cdot K^T$), where both matrices are transient activations.

Model 1 implements **runtime dataflow switching** across three execution paradigms:
1. **Weight-Stationary (WS, `2'b00`)**
2. **Output-Stationary (OS, `2'b01`)**
3. **Input-Stationary (IS, `2'b10`)**

A single tenant occupies the entire physical $M \times N$ systolic mesh. Dataflow selection is controlled dynamically per workload tile via the control bus without requiring FPGA bitstream reconfiguration or power-cycling.

---

## 2. Processing Element (PE) Microarchitecture

Each processing element (`dfs_pe.v`) contains:
- An 8-bit stationary operand register (`stat_operand_reg`)
- An 8-bit signed multiplier
- A 32-bit signed accumulator (`mac_acc`)
- A runtime operand multiplexing network

```
                        [din_n (North)]
                              |
                              v
                   +---------------------+
                   |   dfs_pe Datapath   |
                   |                     |
   [din_w (West)] -+-> [ MUX_A ]  [ MUX_B ] <- [din_n / stat_reg]
                   |        \        /   |
                   |      [ Multiplier ] |
                   |            |        |
                   |      [ 32-bit Acc ] |
                   |            |        |
                   +------------+--------+
                                |
                    [dout_s]    |    [dout_e]
```

### Operand Routing Truth Table

| Mode | `cfg_dataflow_mode` | Multiplier Input A (`mul_a`) | Multiplier Input B (`mul_b`) | Stationary Register Source | Primary Workload Target |
|:---:|:---:|:---:|:---:|:---:|:---|
| **WS** | `2'b00` | `stat_operand_reg` (Weight) | `din_w` (Streaming Activation) | West Port (`din_w`) during `w_ld` | Conv2D, Fully-Connected |
| **OS** | `2'b01` | `din_n` (Streaming Query $Q$) | `din_w` (Streaming Key $K$) | Accumulator registers partial sum | Self-Attention $Q \cdot K^T$ |
| **IS** | `2'b10` | `stat_operand_reg` (Activation) | `din_w` (Streaming Weight) | North Port (`din_n`) during `w_ld` | Depthwise / Pointwise Conv |

---

## 3. 2D Systolic Array Microarchitecture

The array module (`dfs_array.v`) arranges $M$ rows and $N$ columns of PEs into a directional mesh:
- **North-to-South Channels:** Drive column operands (`din_n`). In row $0$, signals originate from external buffer pins. In row $r > 0$, inputs connect combinationally from `dout_s` of row $r-1$.
- **West-to-East Channels:** Drive row operands (`din_w`). In col $0$, signals originate from external buffer pins. In col $c > 0$, inputs connect combinationally from `dout_e` of col $c-1$.
- **Vectorized Module Boundary:** All multi-dimensional ports are packed into 1D vectors (`[NUM_COLS*DATA_W-1:0]`) to ensure clean elaboration in both Verilator and standard synthesis tools.

---

## 4. Operational Phases & Cycle Mechanics

A tile computation proceeds through three sequential phases:

```
+--------------------------------------------------------------------------------+
| Phase 1: Tile Configuration & Accumulator Clear                                 |
| - Drive `cfg_dataflow_mode` (WS, OS, or IS)                                     |
| - Assert `tile_acc_clr = 1'b1` for 1 cycle                                      |
+--------------------------------------------------------------------------------+
                                       |
                                       v
+--------------------------------------------------------------------------------+
| Phase 2: Stationary Preload (WS / IS modes only)                               |
| - Assert `tile_w_ld = 1'b1`                                                    |
| - Drive stationary coefficients on boundary ports (`din_w` for WS, `din_n` for IS)|
| - PEs capture stationary operand into `stat_operand_reg`                       |
+--------------------------------------------------------------------------------+
                                       |
                                       v
+--------------------------------------------------------------------------------+
| Phase 3: Streaming Compute & Accumulation                                       |
| - Assert `tile_compute_en = 1'b1`                                               |
| - Stream dynamic operands across boundaries                                     |
| - Each PE accumulates products: `mac_acc <= mac_acc + (mul_a * mul_b)`          |
+--------------------------------------------------------------------------------+
```

---

## 5. Architectural Strengths and Limitations

### Strengths
1. **Zero Spatial Fragmentation:** Single tenant achieves 100% array utilization on sufficiently large matrix tiles.
2. **Workload-Matched Energy:** Switching to OS mode avoids streaming accumulators through memory hierarchies for attention operations.

### Limitations (The Multi-Tenancy Bottleneck)
1. **Head-of-Line (HoL) Blocking:** When concurrent small models (e.g., CNN + Attention) arrive, one must wait in an external queue until the other completes its entire tile sequence.
2. **Under-Utilization on Small Batches:** A small $2 \times 2$ matrix running on an $8 \times 8$ array leaves $75\%$ of PEs completely idle. Spatial fission is required to eliminate this inefficiency.
