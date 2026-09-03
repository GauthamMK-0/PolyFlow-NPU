# DRDS-NPU Baseline Architecture — Part 1: Spatial Fission & Ownership Safety

**Document status:** Baseline specification (Stage 1)
**Companion document:** `dataflow_switching_baseline.md` (PE dataflow operation + bandwidth arbitration)

---

## Table of Contents

1. [Scope](#1-scope)
2. [Fission Model](#2-fission-model)
3. [Configuration Path — Pod Fission Decoder](#3-configuration-path--pod-fission-decoder)
4. [Region Reassignment Sequence](#4-region-reassignment-sequence)
5. [Boundary Isolation](#5-boundary-isolation)
6. [Bank Ownership Layer — OTP + Scrub](#6-bank-ownership-layer--otp--scrub)
7. [Safety Invariants](#7-safety-invariants)
8. [Worked Example — Split Shift at Dispatch](#8-worked-example--split-shift-at-dispatch)
9. [Interface Reference](#9-interface-reference)
10. [Parameter Defaults](#10-parameter-defaults)
11. [Verification Checklist](#11-verification-checklist)

---

## 1. Scope

This document specifies the **fission subsystem** of the DRDS-NPU pod: the mechanism
that partitions one physical PE array into independently-operating regions at
dispatch time, and the ownership-safety machinery (token protocol + mandatory
scrubbing) that lets memory banks migrate between those regions without races or
data leakage.

It deliberately does **not** specify how each region computes internally
(dataflow selection, PE datapath, bandwidth phase profiles) — that is covered in
`dataflow_switching_baseline.md`. The two documents share the parameter set in
§10 and must agree on every crossed signal (`region_id_mask`,
`region_reassign_bus`, `bank_role_stale`/`bank_role_clear`).

**Baseline envelope (Stage 1):**

| Property | Value |
|---|---|
| Array | One pod, 16 × 16 HDF-PEs (NUM_COLS = 16) |
| Regions | Exactly 2 (Region A = `region_id 0`, Region B = `region_id 1`) |
| Fission granularity | Whole columns |
| Fission timing | Dispatch-time static (between tile launches, never mid-tile) |
| Shared memory | 4 SRAM banks per pod, single owner at a time |

Bounding to two regions bounds the correctness surface: the ownership-token FSM
is exhaustively simulable, and the region×role contract space stays at 2 × 4 =
8 combinations. Dynamic mid-execution fission remains a documented future
extension, not part of this baseline.

> **Deliberate deviation from `architecture.md`:** the OTP is upgraded from the
> draft's non-sticky re-grant scheme to a **sticky single-writer lock with an
> explicit `token_release` input** (see §6.1). Ownership now persists until the
> owner releases it or scrubbing forces release. All other deviations from the
> draft (parameter-width masks, fixed literals) are flagged inline.

---

## 2. Fission Model

### 2.1 What fission means here

Spatial fission splits the PE grid into two vertical sub-arrays that execute
independently:

```
        cols 0 .. S-1              cols S .. 15
   ┌────────────────────┐    ┌────────────────────┐
   │      Region A      │    │      Region B      │
   │   (region_id = 0)  │    │   (region_id = 1)  │
   │  any dataflow      │ ✗  │  any dataflow      │
   │  own banks via OTP │gate│  own banks via OTP │
   └────────────────────┘    └────────────────────┘
                    ▲                ▲
                    └── split column ┘
                        S = cfg_split_col
```

- Every PE column `c` belongs to **Region A iff `c < cfg_split_col`**, else
  Region B. Ownership is per-*column*; rows are never split.
- Regions are asynchronous in progress but synchronous in clock. Each has its
  own phase tag, its own bank token requests, and its own tile schedule.
- No operand, partial sum, or control crosses the split column in either
  direction once the boundary is active (see §5).

### 2.2 Why dispatch-time static

Region boundaries are written by the host scheduler *before* a tile pair
launches and hold for the entire co-execution window. This matches the standard
execution model of spatial multitasking accelerators (Planaria-style) and buys:

- No mid-tile index corruption (address generators never see a moving boundary).
- A static `region_id_mask` that the isolation logic (§5) can compare against
  combinationally with zero re-timing risk.
- A verification surface bounded to mask-transition events rather than
  arbitrary boundary trajectories.

The cost is flexibility: resizing requires draining both regions' current tiles
(or at least quiescing the affected columns). This baseline accepts that cost;
removing it is the future dynamic-fission extension.

### 2.3 Configurable envelope

`cfg_split_col` is 4 bits (0–15):

| `cfg_split_col` | Resulting split |
|---|---|
| `0` | All 16 columns → Region B (degenerate: A empty) |
| `1`–`15` | Normal splits: A gets `S` columns, B gets `16 − S` |
| `16` (all-A) | **Not representable** in 4 bits — documented envelope limit |

A degenerate split (`0`) is legal hardware-wise; the scheduler simply must not
dispatch work to an empty region.

---

## 3. Configuration Path — Pod Fission Decoder

### 3.1 Behavior

The Pod Fission Decoder is the sole writer of region identity. Per clock cycle:

1. On reset, `region_id_mask` and `region_id_prev` initialize to the default
   8-column split (`cols 0–7 → A`, `cols 8–15 → B`).
2. When `cfg_update_strobe` pulses (1 cycle):
   - `region_id_prev ← region_id_mask`
   - New mask registered: `region_id_mask[c] ← (c >= cfg_split_col)`
     (0 = A, 1 = B)
   - `region_reassign_bus[c] ← region_id_prev[c] != new_mask[c]` — a **1-cycle
     pulse per column whose ownership changed**
3. All other cycles: `region_reassign_bus = {NUM_COLS{1'b0}}`.

The comparison for the reassign pulse uses the **registered** old mask against
the newly computed values, so the pulse width is exactly one cycle regardless
of how long the strobe is asserted (strobe is still required to be a single-
cycle pulse by protocol).

### 3.2 Timing

```
            ___         ____________________________
clk        /   \_______/    \_______________________
                ______
cfg_split_col--<  8   >-------------------------------  (stable ≥ setup)
                ____
strobe_________/    \___________________________________
                     ___________ _______________________
region_id_mask------X__old_____X_______new______________   (registered @ strobe cycle+1)
                     _____
reassign_bus[changed]     \___/__________________________   (exactly 1 clk)
```

### 3.3 Correctness notes (fixed vs. draft)

| Draft issue | Fix in this baseline |
|---|---|
| Reset value hardcoded `16'hFF00` ignoring `NUM_COLS` | Mask computed from parameters: default split = `NUM_COLS/2`; all masks sized `{NUM_COLS{...}}` |
| Reassign compare mixed old/new evaluation order | Single registered-compare formulation as in §3.1 step 2 |
| Corrupted literal `1 me0` in listing | Restored to `1'b0` |

---

## 4. Region Reassignment Sequence

When a column changes ownership (pulse on `region_reassign_bus[c]`), four
mechanisms fire in a fixed order. This is the heart of fission safety.

```
 reassign pulse
      │
      ▼
┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐
│ 1. STALE          │   │ 2. DRAIN          │   │ 3. GATE           │
│ PE sets           │──►│ PE loads          │──►│ boundary logic    │
│ bank_role_stale=1 │   │ lifetime_init and │   │ re-partitions     │
│ (blocks bank use) │   │ counts down; MAC  │   │ operand paths at  │
│                   │   │ gated off at 0    │   │ the new split col │
└───────────────────┘   └───────────────────┘   └───────────────────┘
                                                          │
                              ┌───────────────────────────┘
                              ▼
                   ┌───────────────────────┐
                   │ 4. BANK HANDOVER      │
                   │ new owner takes token │
                   │ (OTP) → scrub (§6) →  │
                   │ bank_role_clear pulse │
                   │ clears stale flags    │
                   └───────────────────────┘
```

1. **Stale latch.** Every PE receiving `region_reassign = 1` sets
   `bank_role_stale = 1` synchronously with the pulse. While stale, the PE's
   memory-facing requests are invalid — the PE may finish computing on
   in-flight operands but must not initiate new bank traffic.
2. **Lifetime drain.** The PE loads `lifetime_init` (supplied by the region
   controller) into its LIFETIME_W-bit counter and continues executing MACs
   only while `lifetime_cnt != 0`. This ages out partial sums that are
   physically inside the PE datapath at the moment of handover, so nothing
   half-computed from Region A's tile is ever attributed to Region B.
3. **Boundary regating.** Described in §5; effective on the cycle after the
   mask update registers.
4. **Bank handover.** Any bank changing hands goes through the OTP + scrub
   handshake in §6. Only after `bank_role_clear` pulses do the acquiring
   region's PEs drop `bank_role_stale` and resume memory traffic.

Steps 1–3 complete within `lifetime_init + 2` cycles of the pulse and require
no arbitration. Step 4 is event-driven and overlaps steps 1–3 where possible.

---

## 5. Boundary Isolation

Isolation is implemented in the **array wrapper**, not inside each PE: the
wrapper knows the whole `region_id_mask`, so it can gate crossing paths with
one comparator per boundary instead of comparators per PE.

### 5.1 Rules

Let `mask[c]` be the registered region id of column `c`. For every pair of
horizontally adjacent columns `(c, c+1)` with `mask[c] != mask[c+1]`:

| Crossing path | Behavior at boundary |
|---|---|
| Eastbound operand stream (`dout_e[c]` → `din_w[c+1]`) | Forced to zero at the receiving edge; Region B injects its own eastbound stream at its leftmost column |
| Westbound operand stream (`din_e[c+1]` ← `dout_w[c]`) | Forced to zero at the receiving edge; Region A terminates its own westbound stream |
| Southbound partial sums (`dout_s`) | Never cross columns — allowed unconditionally within each column |
| North/south control (preloads, drains) | Unaffected; they are per-column already |

East/west operand injection points are therefore **per-region edge ports**:
each region drives its row-start independently, and the boundary gate makes
the far region look like an array edge.

### 5.2 Properties

- Zero leakage: no bit of Region A operand state reaches any Region B PE
  combinationally or sequentially through the mesh.
- Zero cost away from the boundary: only the single split pair is gated;
  intra-region hops are untouched wires.
- Re-timing safe: the gate select comes straight off the registered
  `region_id_mask`, so it flips exactly when the decoder commits a new split,
  one cycle after strobe.

---

## 6. Bank Ownership Layer — OTP + Scrub

Four shared SRAM banks sit outside the PE array. Any bank may serve any region
in any role, so two hazards exist whenever a bank changes hands: **double
ownership** (two regions drive/read one bank) and **residual-data leakage**
(new owner reads the old owner's bytes). Two cooperating controllers remove
both.

### 6.1 Ownership Token Protocol (OTP) — one instance per bank

A sticky single-writer lock with epoch-rotating priority.

**FSM (3 states):**

| State | Meaning | Exit condition |
|---|---|---|
| `FREE` | No owner | Any `token_req[i]` → arbitrate, grant, enter `OWNED(i)` |
| `OWNED(r)` | Region `r` holds the token | `token_release[r]` → `FREE`; `scrub_active` → `SCRUB` |
| `SCRUB` | Bank being zeroed for pending owner | scrub done → grant pending requester (or `FREE`) |

**Arbitration:** when `FREE` and multiple regions request, the winner is the
first requesting region in rotation starting at `priority_base`. `priority_base`
increments once per `EPOCH_W`-bit epoch counter wrap (default 255 cycles),
guaranteeing starvation freedom across epochs and denying any region a static
priority position (also blunts naive timing-channel inference from fixed
arbitration order).

**Interface behavior:**

- `grant[i]` is a **1-cycle pulse** at acquisition — not a level.
- `token_owner` register persists through `OWNED`.
- If the owner deasserts nothing and never releases, it keeps the lock;
  other requesters simply wait. There is no timeout by design (correctness
  first; liveness is the scheduler's job).
- `scrub_active` (from the bank's scrub controller) preempts ownership
  unconditionally — safety beats liveness.

> **Deviation from draft RTL:** the draft recomputed `grant`/`token_held`
> combinationally from live request levels, so ownership evaporated the moment
> a region stopped asserting `token_req`. This baseline replaces that with the
> persistent FSM above plus a `token_release` input. The single-writer
> invariant is now enforced by state, not by construction of a combinational
> encoder.

### 6.2 Bank Role Scrub Controller — one instance per bank

Mandatory zeroing pass between owners (and between roles for the same owner).

**Protocol:**

1. Scheduler asserts `role_reassign` together with `new_region_id` and
   `new_role` (role encodings live in `dataflow_switching_baseline.md` §6.2).
2. Scrub controller raises `scrub_active` for exactly `SCRUB_CYC = 4` cycles.
   During this window: the OTP is forced out of `OWNED`; the bank's write port
   is dedicated to the zero-fill pass; the acquiring region's PEs are (or
   become) stale.
3. On completion, one-cycle `bank_role_clear` pulse. The scrub controller
   latches `region_owner ← new_region_id`, `role_tag ← new_role` at the same
   moment.
4. `bank_role_clear` fans out to the acquiring region's PEs, clearing
   `bank_role_stale` and releasing them to issue memory traffic against the
   bank.

**Cycle-exact count:** `scrub_cnt` loads `SCRUB_CYC`, decrements once per
cycle; `scrub_active` spans exactly 4 cycles and `bank_role_clear` pulses on
the cycle after `scrub_cnt` reaches 1. Total occupancy of the handover
critical section: 1 (request) + 4 (scrub) + 1 (clear) = 6 cycles minimum.

### 6.3 Handshake summary

```
Region X                OTP(bank k)            Scrub(bank k)         Region Y PEs
   │  token_req[k]=1       │                        │                    │
   ├──────────────────────►│ grant[X] (1 cyc)       │                    │
   │                       │ state=OWNED(X)         │                    │
   │  (scheduler decides to hand over)             │                    │
   ├──────────────────────────────────────────────► │ role_reassign      │
   │                       │◄─── scrub_active=1 ────┤ (forces SCRUB)     │
   │                       │    4 cycles zeroing    │                    │
   │                       │                        │ bank_role_clear ──►│ stale:=0
   │  token_release (owner-side, may precede/follow scrub)                  │
   │                       │ state=FREE or OWNED(Y) │ commit owner/tag   │
```

---

## 7. Safety Invariants

The fission subsystem claims correctness under five invariants. Each maps to a
concrete check in §11.

| # | Invariant | Enforced by |
|---|---|---|
| I1 | At most one region holds any bank's token in any cycle | OTP FSM: `grant` one-hot, `OWNED(r)` single-owner state |
| I2 | No bank read by an acquiring region before scrub completes | `bank_role_stale` blocks PE memory ops until `bank_role_clear` |
| I3 | No operand bit crosses the split column in either direction | Boundary gating off registered `region_id_mask` (§5) |
| I4 | No PE computes on behalf of its old region after handover beyond the drain window | Lifetime counter gating (§4 step 2) |
| I5 | `region_id_mask` changes only on strobe, atomically | Sole-writer decoder, registered update (§3) |

Liveness (starvation freedom) is guaranteed probabilistically-per-epoch by
rotating priority, not per-request — a documented trade: correctness invariants
I1–I5 are absolute; fairness is eventual.

---

## 8. Worked Example — Split Shift at Dispatch

Scenario: pod running with split at column 12 (A = cols 0–11 on a CNN tile,
B = cols 12–15 idle). Scheduler dispatches a transformer head onto B and moves
the boundary left to column 8, transferring cols 8–11 from A to B.

| Cycle | Event |
|---|---|
| 0 | Host drives `cfg_split_col = 8`, pulses `cfg_update_strobe`. |
| 1 | Decoder registers `region_id_mask = 16'hFF00`. Columns 8–11 receive a 1-cycle `region_reassign` pulse; boundary gate pair (col 7↔8) activates. Those PEs latch `bank_role_stale = 1` and load `lifetime_init`. |
| 2 – (2+L−1) | Transferred PEs drain in-flight partial sums South; MACs gate off as each `lifetime_cnt` hits 0. Region A's west-side streams terminate at col 7; Region B begins injecting its own streams at col 8 (its PEs consume only zeros from the west until B's own feed starts). |
| 3 | Scheduler asserts `token_req_B[bank0]` (B wants A's former weight bank as its activation bank). OTP: `FREE` → arbitrate → `grant_B` pulse, `token_owner = B`. |
| 4 | Scheduler asserts `role_reassign[bank0]`, `new_region_id = B`, `new_role = INPUT_ISSUER`. Scrub raises `scrub_active`; OTP forced `OWNED(B)` → `SCRUB`. |
| 5–8 | Four-cycle zero fill of Bank 0. |
| 9 | `bank_role_clear` pulses. Scrub commits `region_owner=B`, `role_tag=INPUT_ISSUER`. B's PEs in cols 8–11 clear `bank_role_stale`. OTP returns to `OWNED(B)`. |
| 10+ | Steady state: A (cols 0–7) continues its WS CNN tile on Banks 1–3; B (cols 8–15) runs its OS attention tile streaming from Bank 0. Neither region observes the other. |

Note the overlap: the lifetime drain (cycles 2–9ish) and the scrub (4–9)
proceed concurrently because they touch disjoint resources (PE datapaths vs.
bank contents). Correctness needs only that both finish before B issues reads
— guaranteed by I2's stale gate, whichever finishes later.

---

## 9. Interface Reference

### 9.1 pod_fission_decoder

| Port | Dir | Width | Purpose |
|---|---|---|---|
| `clk, rst_n` | in | 1 | Clock, active-low async reset |
| `cfg_split_col` | in | 4 | Split column index (0–15) |
| `cfg_update_strobe` | in | 1 | 1-cycle commit pulse |
| `region_id_mask` | out | 16 | Registered ownership (0=A, 1=B) |
| `region_reassign_bus` | out | 16 | 1-cycle pulse per transferred column |

### 9.2 otp_token_fsm (per bank)

| Port | Dir | Width | Purpose |
|---|---|---|---|
| `clk, rst_n` | in | 1 | Clock, active-low async reset |
| `token_req[NUM_REGIONS-1:0]` | in | 2 | Level: region wants token |
| `token_release[NUM_REGIONS-1:0]` | in | 2 | Pulse: owner surrenders token |
| `scrub_active` | in | 1 | From scrub controller; forces `SCRUB` state |
| `grant[NUM_REGIONS-1:0]` | out | 2 | 1-cycle acquisition pulse, one-hot |
| `token_owner` | out | 1 | Current owner (valid while owned) |
| `token_held` | out | 1 | Status: `OWNED` or `SCRUB-for-owner` |

### 9.3 pod_bank_scrub (per bank)

| Port | Dir | Width | Purpose |
|---|---|---|---|
| `clk, rst_n` | in | 1 | Clock, active-low async reset |
| `role_reassign` | in | 1 | Start scrub for this bank |
| `new_region_id` | in | 1 | Acquiring region |
| `new_role` | in | 2 | Role to commit (encoding: see companion doc §6.2) |
| `scrub_active` | out | 1 | High exactly `SCRUB_CYC` cycles |
| `bank_role_clear` | out | 1 | 1-cycle completion pulse |
| `region_owner` | out | 1 | Committed owner (post-clear) |
| `role_tag` | out | 2 | Committed role (post-clear) |

### 9.4 hdf_pe (fission-relevant slice)

| Port | Dir | Width | Purpose |
|---|---|---|---|
| `region_id` | in | 1 | From `region_id_mask` column bit |
| `region_reassign` | in | 1 | From `region_reassign_bus` column bit |
| `lifetime_ld` / `lifetime_init` | in | 1 / 4 | Drain-window load |
| `bank_role_stale` | out | 1 | Blocks memory traffic while set |
| `bank_role_clear` | in | 1 | Clears stale (fanout from owning bank's scrubber) |

---

## 10. Parameter Defaults

| Parameter | Default | Used by |
|---|---|---|
| `NUM_COLS` | 16 | decoder, array wrapper, mask widths |
| `NUM_REGIONS` | 2 | OTP, EPPA (companion doc) |
| `REGION_W` | 1 | `$clog2(NUM_REGIONS)` |
| `EPOCH_W` | 8 | OTP priority rotation period (255 cycles) |
| `SCRUB_CYC` | 4 | scrub duration |
| `LIFETIME_W` | 4 | PE drain counter (max window 15 cycles) |
| `DATA_W` | 8 | operand width (signed; see companion doc §3) |
| `ACC_W` | 32 | accumulator width (see companion doc §3) |
| `BW_W` | 8 | EPPA allocation granularity (companion doc §7) |
| `NUM_BANKS` | 4 | OTP/scrub instances per pod |

---

## 11. Verification Checklist

Maps to the master verification plan; items here cover fission-specific
correctness.

| Check | Method | Pass criterion |
|---|---|---|
| V1 Decoder masks & pulses | TB: drive splits 4/8/12/0/15 | Mask exact per §2.3 table; pulses exactly 1 cycle, only on changed columns |
| V2 Strobe atomicity | TB: back-to-back strobes, mid-update sampling of mask | Mask never observed partially updated (I5) |
| V3 OTP exhaustiveness | TB: sweep all `token_req`/`token_release`/`scrub_active` combinations across randomized sequences | `grant` never multi-hot; `token_owner` unique while held; no grant during `SCRUB` (I1) |
| V4 Starvation bound | TB: two permanent requesters, observe grants over >2 epochs | Both granted within one rotation window |
| V5 Scrub timing | TB: cycle-exact | `scrub_active` high exactly 4 cycles; `bank_role_clear` 1 cycle; owner/tag commit coincident with clear |
| V6 Boundary isolation | Integration TB: monitors on all crossing wires at split pair | Zero non-zero samples on gated paths during steady state (I3) |
| V7 Drain-before-handover | Integration TB: scoreboard on transferred PEs' last MAC cycle vs. first B-attributed op | No MAC output after `lifetime_cnt == 0` (I4) |
| V8 End-to-end worked example | §8 replay as directed TB | Final outputs match golden model; no stale-flag violations |
| V9 Gate-count budget | Yosys `synth` + `stat` | Control overhead ≤ 13% of PE-array area estimate |

---

## 12. Ablation Knobs (Comparison Support)

This section defines the fission-side configuration knob that lets the
baseline RTL degenerate into the comparison configurations of
`evaluation_framework.md` §1. The knob is additive: it changes no behavior
described in §2–§11 when deasserted.

### 12.1 `SINGLE_TENANT` (pod-level input)

Serializes execution onto one tenant occupying the full 16-column span,
realizing **Config B** ("sequential dataflow switching") — the whole-array
capability fraction of per-layer dataflow switching without co-execution.

| Component | Behavior when `SINGLE_TENANT = 1` |
|---|---|
| Pod Fission Decoder | `region_id_mask` forced to all-Region-A (`{NUM_COLS{1'b0}}`); `cfg_split_col` ignored; a single reassign-pulse burst fires on the assertion edge; subsequent strobes have no effect until the knob is released |
| Scheduler | Issues tiles strictly serially (one outstanding tile pod-wide); dataflow remains freely selectable per tile by the region controller |
| Region B lane | Dormant: no tiles dispatched, `phase_tag[B]` tied to `IDLE (01)`, `token_req_B` tied low |
| EPPA | Lane B naturally pinned to zero bandwidth via its IDLE tag — no arbiter change |
| OTP + Scrub | Unchanged. The single tenant still acquires and releases banks through the full protocol, so handover costs are measured identically across all comparison configurations |
| Exit (`SINGLE_TENANT → 0`) | Next `cfg_update_strobe` restores strobe-driven split; the transition counts as a boundary shift with the normal drain window (§4) |

**Fairness note:** forcing the full span (rather than letting a single tenant
run in an 8-column half) preserves the whole-array reshape capability that
defines the sequential-switching idea; capping the span would handicap Config
B relative to C for reasons unrelated to the ideas under comparison.

**Measurement note:** the mask-forcing transition on knob assertion happens
before the first measured dispatch; steady-state metrics
(`evaluation_framework.md` §4) therefore exclude it.

Consumed by: `evaluation_framework.md` §1 (Config B), §2 (knob wiring table).

Config B as realized by this knob:

![Config B — sequential dataflow switching](figures/figB_seq_switch.png)

---

*DRDS-NPU Fission Baseline — Stage 1 · Two regions · Dispatch-time static split · Sticky ownership tokens*
