# Architecture Specification: Dataflow Switching Model (Model 1)

> **Intuitive Summary:**
> Think of this model like a flexible workshop with one team of workers. When a job needs woodworking, the whole room switches to woodworking tools. When a job needs painting, the whole room switches to paint sprayers. It is optimal for each task type, but only **one job can run at a time**.

---

## 1. Core Idea & The Problem It Solves

In traditional deep learning accelerators (such as Google TPU v1), the processing elements (PEs) are hardwired to **Weight-Stationary (WS)** dataflow:
- Weights are loaded once into PE internal registers and held stationary.
- Activations stream through the array from left to right.
- This is great for convolutional layers (CNNs) where the same filter weights are reused across thousands of image pixels.

**The Problem:**
Modern AI models are no longer just CNNs. Modern pipelines use Transformers (e.g., GPT, BERT, ViT) where the primary operation is **Self-Attention** ($Q \cdot K^T$):
- Both matrices ($Q$ and $K$) are dynamic activations that change on every token.
- Forcing a Weight-Stationary array to run Attention requires constantly reloading weights from memory on every cycle, wasting significant bandwidth and power.

**The Model 1 Solution:**
Model 1 introduces **runtime dataflow switching** to a single-tenant array. A single control register (`cfg_dataflow_mode`) instructs every PE in the array to switch its operand routing on-the-fly:
1. `2'b00` — **Weight-Stationary (WS):** Weights stay inside PEs; activations stream through. Best for Conv2D & Dense layers.
2. `2'b01` — **Output-Stationary (OS):** Partial sums accumulate inside PEs; both matrix inputs stream through simultaneously. Best for Transformer Self-Attention ($Q \cdot K^T$).
3. `2'b10` — **Input-Stationary (IS):** Activations stay inside PEs; filter weights stream through. Best for Depthwise Convolutions.

---

## 2. Processing Element (PE) Microarchitecture

Inside each PE (`dfs_pe.sv`), there is an arithmetic datapath with two input multiplexers:

```
                            [din_n (North Input)]
                                      |
                                      v
                        +---------------------------+
                        |       dfs_pe Datapath     |
                        |                           |
   [din_w (West Input)]-+---> [ MUX A ]   [ MUX B ] <--- [stat_reg / din_n]
                        |         \           /     |
                        |        [ Multiplier ]     |
                        |               |           |
                        |      [ 32-bit Accumulator ]
                        |               |           |
                        +---------------+-----------+
                                        |
                            [dout_s]    |    [dout_e]
```

### How the Muxes Route Operands

| Dataflow Mode | Bits | Multiplier Input A (`mul_a`) | Multiplier Input B (`mul_b`) | What Stays Stationary? | What Streams? |
|---|:---:|---|---|---|---|
| **Weight-Stationary (WS)** | `2'b00` | Stationary Register (`stat_reg`) | West Input (`din_w`) | Weight (in `stat_reg`) | Activations (West $\to$ East) |
| **Output-Stationary (OS)** | `2'b01` | North Input (`din_n`) | West Input (`din_w`) | Accumulator (`mac_acc`) | Queries (North $\to$ South), Keys (West $\to$ East) |
| **Input-Stationary (IS)** | `2'b10` | Stationary Register (`stat_reg`) | West Input (`din_w`) | Input Activation | Filter Weights (West $\to$ East) |

---

## 3. 2D Systolic Array Microarchitecture

The array module (`dfs_array.sv`) connects an $M \times N$ grid of PEs in a clean two-dimensional mesh:
- **North-to-South Channels (`din_n` $\to$ `dout_s`):** Streams column operands downwards.
- **West-to-East Channels (`din_w` $\to$ `dout_e`):** Streams row operands rightwards.
- **Single-Tenant Operation:** All rows and columns in the array operate under the **exact same dataflow mode** simultaneously.

```
       din_n[0]    din_n[1]    din_n[2]    din_n[3]
          |           |           |           |
          v           v           v           v
din_w[0]->[ PE 0,0 ]->[ PE 0,1 ]->[ PE 0,2 ]->[ PE 0,3 ]-> dout_e[0]
          |           |           |           |
          v           v           v           v
din_w[1]->[ PE 1,0 ]->[ PE 1,1 ]->[ PE 1,2 ]->[ PE 1,3 ]-> dout_e[1]
          |           |           |           |
          v           v           v           v
       dout_s[0]   dout_s[1]   dout_s[2]   dout_s[3]
```

---

## 4. Cycle-by-Cycle Worked Examples

### Example A: Weight-Stationary Mode (Conv Layer)
1. **Clear Phase (Cycle 0):** `tile_acc_clr = 1'b1` resets all PE accumulators to `0`.
2. **Preload Phase (Cycle 1):** `tile_w_ld = 1'b1`. West input supplies weight `5`. PE captures `stat_reg = 5`.
3. **Compute Phase (Cycles 2–5):** `tile_compute_en = 1'b1`. West input streams activation `3` for 4 consecutive cycles:
   - Cycle 2: `mac_acc = 0 + (5 * 3) = 15`
   - Cycle 3: `mac_acc = 15 + 15 = 30`
   - Cycle 4: `mac_acc = 30 + 15 = 45`
   - Cycle 5: `mac_acc = 45 + 15 = 60`
   - Result: PE holds final convolution result `60`.

### Example B: Output-Stationary Mode (Attention $Q \cdot K^T$)
1. **Clear Phase (Cycle 0):** `tile_acc_clr = 1'b1`. `cfg_dataflow_mode = 2'b01`.
2. **Streaming Phase (Cycles 1–3):** No preload needed! Both operands stream dynamically:
   - Cycle 1: North supplies Query $Q = 4$; West supplies Key $K = 7$.
     `mac_acc = 0 + (4 * 7) = 28`
   - Cycle 2: North supplies $Q = 2$; West supplies $K = 6$.
     `mac_acc = 28 + (2 * 6) = 28 + 12 = 40`
   - Cycle 3: North supplies $Q = 3$; West supplies $K = 5$.
     `mac_acc = 40 + (3 * 5) = 40 + 15 = 55`
   - Result: PE holds final dot-product attention score `55`.

### Example C: Input-Stationary Mode (Depthwise Conv)
1. **Clear Phase (Cycle 0):** `tile_acc_clr = 1'b1`. `cfg_dataflow_mode = 2'b10`.
2. **Preload Phase (Cycle 1):** `tile_w_ld = 1'b1`. North input supplies activation `6`. PE captures `stat_operand_reg = 6`.
3. **Compute Phase (Cycles 2–4):** `tile_compute_en = 1'b1`. West input streams filter weight `4` over 3 consecutive cycles:
   - Cycle 2: `mac_acc = 0 + (6 * 4) = 24`
   - Cycle 3: `mac_acc = 24 + 24 = 48`
   - Cycle 4: `mac_acc = 48 + 24 = 72`
   - Result: PE holds final depthwise convolution result `72`.

---

## 5. Architectural Trade-offs & Limitations

| Advantage | Limitation |
|---|---|
| **Optimal Energy per Layer:** Each neural network layer uses its mathematically best dataflow, cutting memory traffic. | **Head-of-Line (HoL) Queue Blocking:** When two models arrive at the pod, Model 2 must wait in an external queue until Model 1 finishes its entire sequence. |
| **Simple Hardware Control:** One global mode register controls the entire array. | **Poor Utilization on Small Models:** If a small model needs only 4 PEs on a 16×16 array, 252 PEs sit idle. It cannot share the array with another tenant. |

This limitation directly motivates **Spatial Fission (Model 2)** and our **Novel Heterogeneous Fission (Model 3)**.
