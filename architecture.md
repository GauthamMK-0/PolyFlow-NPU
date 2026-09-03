# DRDS-NPU: Dual-Region Dataflow-Switchable Systolic Array
## Complete Architecture Document — Final Year Project

---

## Table of Contents

1. [Why This Design Exists](#1-why-this-design-exists)
2. [Systolic Array Primer — How the PE Array Works](#2-systolic-array-primer)
3. [Top-Level Architecture and Data Flow](#3-top-level-architecture-and-data-flow)
4. [Component 1 — HDF-PE (Processing Element)](#4-component-1--hdf-pe)
5. [Component 2 — EPPA (Pod Memory Arbiter)](#5-component-2--eppa)
6. [Component 3 — OTP (Ownership Token Protocol)](#6-component-3--otp)
7. [Component 4 — Pod Bank Scrub](#7-component-4--pod-bank-scrub)
8. [Component 5 — Pod Fission Decoder](#8-component-5--pod-fission-decoder)
9. [How the Components Wire Together](#9-how-the-components-wire-together)
10. [A Complete Worked Example — Cycle by Cycle](#10-a-complete-worked-example)
11. [Full RTL — All Modules](#11-full-rtl--all-modules)
12. [Verification Plan](#12-verification-plan)
13. [Open Questions & Future Extension Plan](#13-open-questions--future-extension-plan)
14. [References](#14-references)

---

## 1. Why This Design Exists

### The Problem

Modern AI chips must run more than one model at a time. A practical example: a
self-driving car chip runs a CNN backbone (detecting objects in a camera frame) and
a transformer-based prediction head (predicting vehicle trajectories) simultaneously,
both consuming the same input frame. Running them sequentially on a single NPU wastes
latency and compute utilization. Running them truly concurrently on one PE array
requires the array to be split into two independently-operating regions at runtime.

This idea — **spatial fission** — already exists. Planaria (MICRO 2020) does
it. The problem is that Planaria forces every region into the same dataflow: every
sub-array always runs weight-stationary (WS). This is a fundamental limitation because:

- **CNN layers** (convolution, fully-connected) have strong weight reuse. WS is the
  right dataflow — weights are loaded once per tile, inputs stream through.
- **Transformer attention layers** compute Q·Kᵀ and softmax·V, where both operands
  are live activations. There is no naturally stationary operand. WS doesn't fit
  structurally. Output-stationary (OS) is the closest match.

If you co-locate a CNN backbone (wants WS) and a transformer head (wants OS) on a
Planaria-style chip, one of them is running in the wrong dataflow. That costs
throughput, memory bandwidth, or both.

**ReDas** (Han et al.) solves the dataflow flexibility problem — it supports genuine
per-layer WS/OS/IS switching with a derived cost model. But ReDas is single-tenant
and strictly sequential. It has no concurrency story at all.

**The gap this project fills:** neither Planaria nor ReDas nor any combination of them
provides a buffer-arbitration and ownership-safety layer that lets ReDas-style per-region
dataflow selection run inside Planaria-style concurrent regions. Building that layer —
not a new PE datapath, not a new dataflow — is the project's contribution.

### Why Dispatch-Time Static Fission ("Two Regions, One Pod")

Fission in DRDS-NPU is implemented as **dispatch-time static fission**. Before a tile
pair executes, a 4-bit configuration register (`cfg_split_col`) sets the column boundary
(e.g., column 8 divides the 16×16 array into two 8×16 sub-arrays). This matches the
standard execution model of spatial multitasking accelerators (e.g., Planaria), where
region boundaries are set per workload launch, avoiding mid-tile index corruption.

Bounding the design to **two regions in one Pod** keeps:
- The region×role contract space to 2 × 4 = 8 combinations
- The OTP correctness proof to a 4-state FSM (exhaustively simulable)
- The verification surface within two-semester undergraduate scope
- The overhead cost proportional to the benefit

---

## 2. Systolic Array Primer

### What a Systolic Array Is

A systolic array is a grid of Processing Elements (PEs), each connected only to its
immediate neighbors (North, South, East, West). Data flows through the grid like a
wave (systole). Each PE does one multiply-accumulate (MAC) per cycle as data passes
through it.

```
Data flows →  →  →  →
          ↓  ↓  ↓  ↓
PE PE PE PE
↓  ↓  ↓  ↓
PE PE PE PE
↓  ↓  ↓  ↓
PE PE PE PE
```

For a matrix multiplication C = A × B, the PE array computes many MAC operations
in parallel, with A's rows streaming in one direction and B's columns in another.
The key design choice is **which operand stays stationary in each PE**.

### The Three Dataflows

#### Weight-Stationary (WS) — Best for CNN/FC layers

```
Weights preloaded into each PE, held stationary for the entire tile.

→ → → → Inputs (activations) stream East through each row
         ↓ ↓ ↓ ↓  Partial sums drain South to output collector

Each PE: acc += weight_stationary × input_streaming
```

#### Output-Stationary (OS) — Best for Attention / zero-stationary-operand layers

```
Each PE owns one output element and accumulates into it across the full tile.

→ → → → One operand streams East (e.g., queries Q)
↓ ↓ ↓ ↓  Other operand streams South (e.g., keys K)

Each PE: my_output += operand_a_streaming × operand_b_streaming
```

#### Input-Stationary (IS) — Best for specific depthwise convolutions

```
Input activations preloaded and held stationary.
Weights stream East, partial sums stream South.

Each PE: acc += input_stationary × weight_streaming
```

---

## 3. Top-Level Architecture and Data Flow

### Physical Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DRDS-NPU Pod                                  │
│                                                                       │
│   cfg_split_col ──► ┌──────────────────────┐                         │
│   cfg_update_str──► │ Pod Fission Decoder  │                         │
│                     └──────────┬───────────┘                         │
│                                │ region_id_mask                      │
│                                │ region_reassign_bus                 │
│  ┌─────────────────────────────▼───────────────────────────────┐    │
│  │              Pod Memory — 4 shared banks                     │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │    │
│  │  │  Bank 0  │  │  Bank 1  │  │  Bank 2  │  │  Bank 3  │   │    │
│  │  │ role_tag │  │ role_tag │  │ role_tag │  │ role_tag │   │    │
│  │  │ reg_own  │  │ reg_own  │  │ reg_own  │  │ reg_own  │   │    │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │    │
│  └───────┼─────────────┼─────────────┼─────────────┼──────────┘    │
│          │             │             │             │                  │
│  ┌───────▼─────────────▼─────────────▼─────────────▼──────────┐    │
│  │               Pod Arbiter                                    │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │    │
│  │  │     EPPA     │  │  OTP (×4,    │  │  Bank Scrub (×4) │  │    │
│  │  │  (bandwidth  │  │  one per     │  │  (mandatory zero  │  │    │
│  │  │  allocation) │  │  bank)       │  │   on role change) │  │    │
│  │  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │    │
│  └─────────┼────────────────┼─────────────────────┼────────────┘    │
│            │                │                     │                  │
│   ┌────────▼────────┐       │           ┌─────────▼───────┐         │
│   │    Region A     │       │           │    Region B     │         │
│   │  WS / OS / IS   │◄──────┘──────────►│  WS / OS / IS  │         │
│   │  (cols 0..N-1)  │  dispatch split   │  (cols N..15)  │         │
│   │                 │  `cfg_split_col`  │                 │         │
│   │  HDF-PE grid    │                   │  HDF-PE grid   │         │
│   └─────────────────┘                   └─────────────────┘         │
└─────────────────────────────────────────────────────────────────────┘
```

### Data Flow Summary

1. **Dispatch Configuration:** Prior to tile launch, the scheduler sets `cfg_split_col` (e.g., 8) and pulses `cfg_update_strobe`. The **Pod Fission Decoder** updates `region_id_mask`, routing PE columns 0–7 to Region A and 8–15 to Region B.
2. **Steady-State Execution:** EPPA manages bank bandwidth between Region A and Region B based on their active phase tags (`BURST`, `IDLE`, `STREAM`).
3. **Reconfiguration & Safety:** When a region completes a tile, OTP arbitrates bank ownership, Bank Scrub zeroes the bank, and `bank_role_clear` releases PEs to safely execute the next tile.

---

## 4. Component 1 — HDF-PE

### Why It Exists

The PE is the fundamental compute unit. Each PE provides:
1. **Runtime-selectable dataflow mode** (WS / OS / IS).
2. **Lifetime counter** — ages out in-flight partial sums during boundary shifts.
3. **bank_role_stale flag** — gates bank reads until mandatory scrubbing completes.

### Interface Summary

| Port | Direction | Width | Purpose |
|---|---|---|---|
| `clk, rst_n` | In | 1 | Clock, active-low reset |
| `din_n/s/e/w` | In | DATA_W | Data from N/S/E/W neighbors |
| `dout_n/s/e/w` | Out | DATA_W | Data to N/S/E/W neighbors |
| `dataflow_mode` | In | 2 | 00=WS, 01=OS, 10=IS, 11=reserved |
| `region_id` | In | 1 | Which region owns this PE (0=A, 1=B) |
| `region_reassign` | In | 1 | Pulse: this PE is being transferred |
| `route_sel` | In | 4 | Which neighbor ports carry operands vs. pass-through |
| `lifetime_ld` | In | 1 | Load lifetime_init into counter |
| `lifetime_init` | In | LIFETIME_W | Initial countdown value |
| `bank_role_stale` | Out | 1 | High = bank scrub not yet complete |
| `bank_role_clear` | In | 1 | Pulse from scrub controller: now safe |

---

## 5. Component 2 — EPPA

### Why It Exists

Manages physical memory bandwidth between heterogeneously-operating regions. It recomputes bandwidth allocation **only on phase-transition events** (burst, idle, streaming, reconfig) and pins the result, eliminating per-cycle arbitration overhead.

| Phase Tag | Value | Meaning | Bandwidth Allocation |
|---|---|---|---|
| Burst | `2'b00` | Preloading weights / draining psums | Maximum (Full) |
| Idle | `2'b01` | Compute phase (data stationary) | Zero |
| Streaming | `2 me10` | Continuous OS streaming | Half |
| Reconfiguring | `2'b11` | Tile drain + new tile setup | Maximum + High Priority |

---

## 6. Component 3 — OTP

### Why It Exists

Eliminates bank ownership race conditions when two regions enter reconfiguration simultaneously. 

* **Single-writer token per bank:** Only the token holder may trigger a bank role change.
* **Rotating priority:** Flips priority base each epoch to guarantee starvation-free access and prevent timing-channel leakage.
* **Correctness invariant:** At no cycle can both regions hold the token for the same bank.

---

## 7. Component 4 — Pod Bank Scrub

### Why It Exists

When a memory bank's role changes (e.g., from weight-issuer for Region A to input-issuer for Region B), residual data could leak into the new region's activation path.

* **Mandatory 4-cycle zeroing pass:** Holds `scrub_active=1` for `SCRUB_CYC` cycles.
* **Handshake:** Emits `bank_role_clear=1` upon completion, clearing the `bank_role_stale` flag across PEs in the new region.

---

## 8. Component 5 — Pod Fission Decoder

### Why It Exists

The **Pod Fission Decoder** provides hardware support for **dispatch-time static spatial fission**. Rather than hardcoding the PE split point, the host scheduler writes a 4-bit value to `cfg_split_col` before launching a workload pair.

### What It Does

1. Accepts `cfg_split_col` (0–15) and a 1-cycle `cfg_update_strobe` pulse.
2. Evaluates `(col >= cfg_split_col)` for all 16 PE columns to generate a 16-bit `region_id_mask` (0 = Region A, 1 = Region B).
3. Compares the new mask against `region_id_prev`. Columns whose ownership changed receive a 1-cycle pulse on `region_reassign_bus`, triggering lifetime-counter flushes in those PEs.

### Interface Summary

| Port | Direction | Width | Purpose |
|---|---|---|---|
| `clk, rst_n` | In | 1 | Clock, active-low reset |
| `cfg_split_col` | In | 4 | Split column index (0..15) |
| `cfg_update_strobe` | In | 1 | Pulse: commit new split boundary |
| `region_id_mask` | Out | 16 | Per-column region ownership (0=A, 1=B) |
| `region_reassign_bus` | Out | 16 | Per-column reassign pulse to trigger lifetime drain |

---

## 9. How the Components Wire Together

```
   cfg_split_col ────► Pod Fission Decoder ──► region_id_mask ────────► HDF-PE Array
   cfg_update_str ───►                      ──► region_reassign_bus ──► HDF-PE Array

   phase_tag ────────► EPPA Arbiter ─────────► bw_alloc ──────────────► DMA / Bus
                                    ─────────► reconfig_active ────────► Scheduler Priority

   token_req_A/B ────► OTP (×4 Banks) ───────► grant ─────────────────► Local Controllers
                          ▲
                          │ scrub_active
                          │
                       Bank Scrub (×4) ──────► bank_role_clear ────────► HDF-PE Array
```

---

## 10. A Complete Worked Example — Cycle by Cycle

### Scenario: Dispatching a 8×16 Split (Region A: CNN, Region B: Attention)

1. **Cycle 0 (Dispatch Configuration):** Scheduler sets `cfg_split_col = 8` and asserts `cfg_update_strobe = 1`.
2. **Cycle 1 (Decoder Execution):** `pod_fission_decoder` updates `region_id_mask = 16'hFF00` (cols 0–7 → Region A, cols 8–15 → Region B). Transferred columns receive `region_reassign_bus` pulses.
3. **Cycles 2–99 (Steady-State Execution):** Region A (WS) preloads Bank 0 and computes. Region B (OS) streams continuously from Bank 2. EPPA allocates bandwidth automatically without cycle-by-cycle re-arbitration.
4. **Cycle 100 (Reconfiguration Request):** Region A finishes tile, signals `phase_tag[A] = 2'b11` (RECONFIG), and requests Bank 0 via OTP.
5. **Cycles 101–105 (Scrub & Release):** OTP grants token. `pod_bank_scrub` zeroes Bank 0 over 4 cycles. `bank_role_clear` pulses, clearing `bank_role_stale` in Region A PEs.
6. **Cycle 106 (Tile Resume):** Region A begins preloading next CNN tile. Region B streams uninterrupted throughout.

---

## 11. Full RTL — All Modules

### 11.1 pod_fission_decoder.v

```verilog
// pod_fission_decoder.v
// Decodes dispatch-time 4-bit split column configuration into per-column PE controls.

module pod_fission_decoder #(
    parameter NUM_COLS = 16
) (
    input  wire                 clk, rst_n,
    input  wire [3:0]           cfg_split_col,        // Split column (0..15)
    input  wire                 cfg_update_strobe,    // Pulse to update boundary

    output reg  [NUM_COLS-1:0]  region_id_mask,       // 0 = Region A, 1 = Region B
    output reg  [NUM_COLS-1:0]  region_reassign_bus   // Reassign pulse per column
);

    reg [NUM_COLS-1:0] region_id_prev;
    integer c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            region_id_mask      <= 16'hFF00; // Default: 8x8 split (cols 0-7 = A, 8-15 = B)
            region_id_prev      <= 16'hFF00;
            region_reassign_bus <= 16'h0000;
        end else if (cfg_update_strobe) begin
            region_id_prev <= region_id_mask;

            // Generate per-column region ID
            for (c = 0; c < NUM_COLS; c = c + 1) begin
                region_id_mask[c] <= (c >= cfg_split_col) ? 1'b1 : 1'b0;
            end

            // Assert reassign pulse for columns whose region assignment changed
            for (c = 0; c < NUM_COLS; c = c + 1) begin
                region_reassign_bus[c] <= (region_id_mask[c] != ((c >= cfg_split_col) ? 1'b1 : 1 me0));
            end
        end else begin
            region_reassign_bus <= 16'h0000; // Deassert pulse
        end
    end

endmodule
```

### 11.2 hdf_pe.v

```verilog
// hdf_pe.v — HDF Processing Element (WS, OS, IS dataflows)
module hdf_pe #(
    parameter DATA_W     = 8,
    parameter LIFETIME_W = 4,
    parameter REGION_W   = 1
) (
    input  wire                   clk, rst_n,
    input  wire [DATA_W-1:0]      din_n, din_s, din_e, din_w,
    output reg  [DATA_W-1:0]      dout_n, dout_s, dout_e, dout_w,

    input  wire [1:0]             dataflow_mode,
    input  wire [REGION_W-1:0]    region_id,
    input  wire                   region_reassign,
    input  wire [3:0]             route_sel,

    input  wire                   lifetime_ld,
    input  wire [LIFETIME_W-1:0]  lifetime_init,

    output reg                    bank_role_stale,
    input  wire                   bank_role_clear
);
    reg [DATA_W-1:0]     stat_operand, operand_a, operand_b;
    reg [2*DATA_W-1:0]   mac_acc;
    reg [LIFETIME_W-1:0] lifetime_cnt;
    wire lifetime_active = (lifetime_cnt != {LIFETIME_W{1'b0}});

    always @(posedge clk or negedge rst_n)
        if (!rst_n)           lifetime_cnt <= {LIFETIME_W{1'b0}};
        else if (lifetime_ld) lifetime_cnt <= lifetime_init;
        else if (lifetime_active) lifetime_cnt <= lifetime_cnt - 1'b1;

    wire [DATA_W-1:0] op_in_n = route_sel[3] ? din_n : {DATA_W{1'b0}};
    wire [DATA_W-1:0] op_in_s = route_sel[2] ? din_s : {DATA_W{1'b0}};
    wire [DATA_W-1:0] op_in_e = route_sel[1] ? din_e : {DATA_W{1'b0}};
    wire [DATA_W-1:0] op_in_w = route_sel[0] ? din_w : {DATA_W{1'b0}};

    always @(*) begin
        case (dataflow_mode)
            2'b00: begin stat_operand = op_in_w; operand_a = op_in_n; operand_b = op_in_e; end // WS
            2'b01: begin stat_operand = {DATA_W{1'b0}}; operand_a = op_in_n; operand_b = op_in_w; end // OS
            2'b10: begin stat_operand = op_in_n; operand_a = op_in_w; operand_b = op_in_e; end // IS
            default: begin stat_operand = {DATA_W{1'b0}}; operand_a = {DATA_W{1'b0}}; operand_b = {DATA_W{1'b0}}; end
        endcase
    end

    // MAC accumulator (placeholder structurally matching port widths)
    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            mac_acc <= {2*DATA_W{1'b0}};
        else if (lifetime_active)
            mac_acc <= mac_acc
                + {{DATA_W{1'b0}}, operand_a} * {{DATA_W{1'b0}}, operand_b}
                + (((dataflow_mode == 2'b00) || (dataflow_mode == 2'b10))
                   ? {{DATA_W{1'b0}}, stat_operand} * {{DATA_W{1'b0}}, operand_a}
                   : {2*DATA_W{1'b0}});

    always @(*) begin
        dout_n = route_sel[3] ? mac_acc[DATA_W-1:0] : din_s;
        dout_s = route_sel[2] ? mac_acc[DATA_W-1:0] : din_n;
        dout_e = route_sel[1] ? mac_acc[DATA_W-1:0] : din_w;
        dout_w = route_sel[0] ? mac_acc[DATA_W-1:0] : din_e;
    end

    always @(posedge clk or negedge rst_n)
        if (!rst_n)            bank_role_stale <= 1'b0;
        else if (region_reassign) bank_role_stale <= 1'b1;
        else if (bank_role_clear) bank_role_stale <= 1'b0;
endmodule
```

### 11.3 eppa_arbiter.v

```verilog
// eppa_arbiter.v — Event-driven Phase-Pinned Arbiter
module eppa_arbiter #(
    parameter NUM_REGIONS = 2,
    parameter BW_W        = 8
) (
    input  wire                        clk, rst_n,
    input  wire [2*NUM_REGIONS-1:0]    phase_tag,
    output reg  [NUM_REGIONS*BW_W-1:0] bw_alloc,
    output reg  [NUM_REGIONS-1:0]      reconfig_active
);
    reg [2*NUM_REGIONS-1:0] phase_tag_prev;
    wire any_transition = (phase_tag != phase_tag_prev);
    integer i;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            phase_tag_prev  <= {2*NUM_REGIONS{1'b0}};
            bw_alloc        <= {NUM_REGIONS*BW_W{1'b0}};
            reconfig_active <= {NUM_REGIONS{1'b0}};
        end else begin
            phase_tag_prev <= phase_tag;
            if (any_transition) begin
                for (i = 0; i < NUM_REGIONS; i = i + 1) begin
                    case (phase_tag[2*i +: 2])
                        2'b00: begin bw_alloc[i*BW_W +: BW_W] <= {BW_W{1'b1}}; reconfig_active[i] <= 1'b0; end
                        2'b11: begin bw_alloc[i*BW_W +: BW_W] <= {BW_W{1'b1}}; reconfig_active[i] <= 1'b1; end
                        2'b10: begin bw_alloc[i*BW_W +: BW_W] <= {1'b0, {(BW_W-1){1'b1}}}; reconfig_active[i] <= 1'b0; end
                        default: begin bw_alloc[i*BW_W +: BW_W] <= {BW_W{1'b0}}; reconfig_active[i] <= 1'b0; end
                    endcase
                end
            end
        end
endmodule
```

### 11.4 otp_token_fsm.v

```verilog
// otp_token_fsm.v — Ownership Token Protocol (rotating priority, synthesis-safe)
module otp_token_fsm #(
    parameter NUM_REGIONS = 2,
    parameter REGION_W    = 1,
    parameter EPOCH_W     = 8
) (
    input  wire                    clk, rst_n,
    input  wire [NUM_REGIONS-1:0]  token_req,
    input  wire                    scrub_active,
    output reg  [REGION_W-1:0]     token_owner,
    output reg                     token_held,
    output reg  [NUM_REGIONS-1:0]  grant
);
    reg [EPOCH_W-1:0] epoch_cnt;
    reg               priority_base;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            epoch_cnt     <= {EPOCH_W{1'b0}};
            priority_base <= 1'b0;
        end else if (epoch_cnt == {EPOCH_W{1'b1}}) begin
            epoch_cnt     <= {EPOCH_W{1'b0}};
            priority_base <= ~priority_base;
        end else begin
            epoch_cnt <= epoch_cnt + 1'b1;
        end

    reg [REGION_W-1:0]   candidate;
    reg                   found;
    reg [NUM_REGIONS-1:0] grant_next;

    always @(*) begin
        found      = 1'b0;
        candidate  = {REGION_W{1'b0}};
        grant_next = {NUM_REGIONS{1'b0}};
        if (token_req[priority_base]) begin
            candidate = priority_base;
            found     = 1'b1;
        end else if (token_req[~priority_base]) begin
            candidate = ~priority_base;
            found     = 1'b1;
        end
        if (found) grant_next[candidate] = 1'b1;
    end

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            token_owner <= {REGION_W{1'b0}};
            token_held  <= 1'b0;
            grant       <= {NUM_REGIONS{1'b0}};
        end else if (scrub_active) begin
            token_held <= 1'b0;
            grant      <= {NUM_REGIONS{1'b0}};
        end else begin
            grant <= grant_next;
            if (found) begin
                token_owner <= candidate;
                token_held  <= 1'b1;
            end else begin
                token_held <= 1'b0;
            end
        end
endmodule
```

### 11.5 pod_bank_scrub.v

```verilog
// pod_bank_scrub.v — Mandatory Bank Scrubbing Controller
module pod_bank_scrub #(
    parameter REGION_W  = 1,
    parameter SCRUB_CYC = 4
) (
    input  wire                 clk, rst_n,
    input  wire                 role_reassign,
    input  wire [REGION_W-1:0]  new_region_id,
    input  wire [1:0]           new_role,
    output reg                  scrub_active,
    output reg                  bank_role_clear,
    output reg  [REGION_W-1:0]  region_owner,
    output reg  [1:0]           role_tag
);
    localparam CNT_W = $clog2(SCRUB_CYC + 1);
    reg [CNT_W-1:0] scrub_cnt;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            scrub_active    <= 1'b0;
            bank_role_clear <= 1'b0;
            scrub_cnt       <= {CNT_W{1'b0}};
            region_owner    <= {REGION_W{1'b0}};
            role_tag        <= 2'b11;
        end else begin
            bank_role_clear <= 1'b0;
            if (role_reassign && !scrub_active) begin
                scrub_active <= 1'b1;
                scrub_cnt    <= SCRUB_CYC[CNT_W-1:0];
            end else if (scrub_active) begin
                scrub_cnt <= scrub_cnt - 1'b1;
                if (scrub_cnt == {{(CNT_W-1){1'b0}}, 1'b1}) begin
                    scrub_active    <= 1'b0;
                    bank_role_clear <= 1'b1;
                    region_owner    <= new_region_id;
                    role_tag        <= new_role;
                end
            end
        end
endmodule
```

### 11.6 drds_npu_pod.v (Top-Level Module)

```verilog
// drds_npu_pod.v — Top-Level Structural Interconnect with Fission Decoder
module drds_npu_pod #(
    parameter BW_W      = 8,
    parameter EPOCH_W   = 8,
    parameter SCRUB_CYC = 4,
    parameter NUM_BANKS = 4,
    parameter NUM_COLS  = 16
) (
    input  wire        clk, rst_n,

    // Dispatch-Time Spatial Fission Configuration
    input  wire [3:0]  cfg_split_col,        // Split column (0..15)
    input  wire        cfg_update_strobe,    // Pulse to update boundary

    // Region Control & Arbitration
    input  wire [3:0]  phase_tag,            // 2b × 2 regions
    input  wire [NUM_BANKS-1:0] token_req_A,
    input  wire [NUM_BANKS-1:0] token_req_B,
    input  wire [NUM_BANKS-1:0] role_reassign,
    input  wire [NUM_BANKS-1:0] new_region_id_per_bank,
    input  wire [2*NUM_BANKS-1:0] new_role_per_bank,

    // Bus / DMA & Status Outputs
    output wire [2*BW_W-1:0]    bw_alloc,
    output wire [1:0]            reconfig_active,
    output wire [NUM_BANKS-1:0]  bank_role_clear_bus,
    output wire [NUM_BANKS-1:0]  scrub_active_bus,
    output wire [NUM_COLS-1:0]   pe_region_id_mask,
    output wire [NUM_COLS-1:0]   pe_reassign_bus
);

    // ─── Instantiate Fission Decoder ──────────────────────────────────────
    pod_fission_decoder #(.NUM_COLS(NUM_COLS)) u_fission_dec (
        .clk                (clk),
        .rst_n              (rst_n),
        .cfg_split_col      (cfg_split_col),
        .cfg_update_strobe  (cfg_update_strobe),
        .region_id_mask     (pe_region_id_mask),
        .region_reassign_bus(pe_reassign_bus)
    );

    // ─── Instantiate EPPA Arbiter ─────────────────────────────────────────
    eppa_arbiter #(.NUM_REGIONS(2), .BW_W(BW_W)) u_eppa (
        .clk            (clk),
        .rst_n          (rst_n),
        .phase_tag      (phase_tag),
        .bw_alloc       (bw_alloc),
        .reconfig_active(reconfig_active)
    );

    // ─── Instantiate Per-Bank OTP & Scrub Controllers ─────────────────────
    genvar b;
    generate
        for (b = 0; b < NUM_BANKS; b = b + 1) begin : bank_ctrl
            wire scrub_wire, clr_wire;

            otp_token_fsm #(.NUM_REGIONS(2), .REGION_W(1), .EPOCH_W(EPOCH_W))
            u_otp (
                .clk          (clk),
                .rst_n        (rst_n),
                .token_req    ({token_req_B[b], token_req_A[b]}),
                .scrub_active (scrub_wire),
                .token_owner  (),
                .token_held   (),
                .grant        ()
            );

            pod_bank_scrub #(.REGION_W(1), .SCRUB_CYC(SCRUB_CYC))
            u_scrub (
                .clk            (clk),
                .rst_n          (rst_n),
                .role_reassign  (role_reassign[b]),
                .new_region_id  (new_region_id_per_bank[b]),
                .new_role       (new_role_per_bank[2*b +: 2]),
                .scrub_active   (scrub_wire),
                .bank_role_clear(clr_wire),
                .region_owner   (),
                .role_tag       ()
            );

            assign scrub_active_bus[b]    = scrub_wire;
            assign bank_role_clear_bus[b] = clr_wire;
        end
    endgenerate

endmodule
```

---

## 12. Verification Plan

1. **Gate-Count Evaluation:** Synthesize all 6 RTL modules using Yosys to verify that total gate overhead remains $\le 13\%$ of array area.
2. **HDF-PE Isolation Test:** Validate WS, OS, and IS math logic, lifetime gating, and `bank_role_stale` setting/clearing.
3. **OTP Correctness:** Run exhaustive 4096-state check to guarantee zero double-grant occurrences (`grant != 2'b11`).
4. **Fission Decoder Test:** Drive `cfg_split_col` with 4, 8, 12; verify `pe_region_id_mask` and verify `pe_reassign_bus` pulses for 1 cycle on changes.
5. **Two-Region Integration Test:** Simulate Region A (WS) and Region B (OS) running concurrently under simultaneous bank requests to verify OTP, Scrub, and EPPA operation without data leakage.

---

## 13. Open Questions & Future Extension Plan

### 13.1 Open Questions

1. **Overhead Budgeting:** Gate-count validation must be confirmed post-synthesis.
2. **Workload Contention:** Requires workload trace profiling to quantify bandwidth savings of EPPA over static assignment.

### 13.2 Future Extension Plan: Fully Dynamic Runtime Fission

While the baseline DRDS-NPU architecture implements dispatch-time spatial fission, extending the system to support **fully dynamic mid-execution runtime fission** (where the chip resizes regions automatically based on live queue depth) is outlined below as a future research expansion:

```
                  ┌──────────────────────────────────────────┐
                  │    Dynamic Runtime Fission Controller    │
                  │              (Future Extension)          │
                  └────────────────────┬─────────────────────┘
                                       │
            ┌──────────────────────────┼──────────────────────────┐
            ▼                          ▼                          ▼
 ┌──────────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
 │  Fission State Mach. │   │  Dynamic Lifetime    │   │  DMA Address Stride  │
 │  (Waits for IDLE tag │   │  Calculator          │   │  Switcher            │
 │  before re-splitting)│   │  (Auto-calculates    │   │  (Adjusts SRAM       │
 └──────────────────────┘   │   flush duration)    │   │   strides per tile)  │
                            └──────────────────────┘   └──────────────────────┘
```

1. **Fission State Machine (FSM):** A hardware manager that monitors region progress (`phase_tag == IDLE`), pauses input streams, triggers boundary shifts safely mid-run, and resumes compute without manual host intervention.
2. **Dynamic Lifetime Calculator:** Automatically calculates $L = (\text{shifted\_cols} \times \text{pipeline\_depth})$ to set `lifetime_init` dynamically during runtime boundary shifts.
3. **DMA Address Stride Switcher:** Reconfigures memory address generators on-the-fly when a region's column width changes from $W_1$ to $W_2$ during execution.

---

## 14. References

1. S. Ghodrati et al., "Planaria: Dynamic Architecture Fission for Spatial Multi-Tenant Acceleration of Deep Neural Networks," *MICRO*, 2020.
2. J. Lee et al., "Dataflow Mirroring: Architectural Support for Highly Efficient Fine-Grained Spatial Multitasking on Systolic-Array NPUs," *DAC*, 2021.
3. M. Han et al., "ReDas: A Lightweight Architecture for Supporting Fine-Grained Reshaping and Multiple Dataflows on Systolic Array," *IEEE TC*, 2024.
4. H. Kwon et al., "Heterogeneous Dataflow Accelerators for Multi-DNN Workloads," *HPCA*, 2021.

---

*DRDS-NPU Architecture Specification — Final Year Project*  
*Scope: Two regions · Dispatch-time static fission · Shared memory safety*
