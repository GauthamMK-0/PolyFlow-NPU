// hdf_top_8x8.sv — Dedicated 8x8 Scaled Pod for Heterogeneous Fission Architecture
// PolyFlow-NPU: 64 Processing Elements with Independent WS/OS/IS Co-Execution & Phase-Pinned Bandwidth

`timescale 1ns/1ps

module hdf_top_8x8 #(
    parameter int DATA_W      = 8,
    parameter int ACC_W       = 32,
    parameter int LIFETIME_W  = 4,
    parameter int NUM_ROWS    = 8,
    parameter int NUM_COLS    = 8,
    parameter int NUM_BANKS   = 2,
    parameter int NUM_REGIONS = 2,
    parameter int REGION_W    = 1,
    parameter int BW_W        = 8,
    parameter int SPLIT_W     = 4
) (
    input  logic                                clk,
    input  logic                                rst_n,

    // Dispatch-Time Spatial Fission Configuration
    input  logic [SPLIT_W-1:0]                  cfg_split_col,
    input  logic                                cfg_update_strobe,

    // Phase tags & arbitration inputs
    input  logic [2*NUM_REGIONS-1:0]            phase_tag,
    input  logic [NUM_BANKS-1:0]                token_req_A,
    input  logic [NUM_BANKS-1:0]                token_req_B,
    input  logic [NUM_BANKS-1:0]                token_release_A,
    input  logic [NUM_BANKS-1:0]                token_release_B,
    input  logic [NUM_BANKS-1:0]                role_reassign,
    input  logic [NUM_BANKS-1:0]                new_region_id_per_bank,
    input  logic [2*NUM_BANKS-1:0]              new_role_per_bank,

    // Per-Region Heterogeneous Dataflow Modes: [1:0]=Region A, [3:2]=Region B
    input  logic [2*NUM_REGIONS-1:0]            dataflow_mode,

    // Per-Region Execution & Lifetime Controls (packed)
    input  logic [NUM_REGIONS-1:0]              lifetime_ld,
    input  logic [NUM_REGIONS*LIFETIME_W-1:0]   lifetime_init,
    input  logic [NUM_REGIONS-1:0]              w_ld,
    input  logic [NUM_REGIONS-1:0]              acc_clr,

    // Mesh streaming data inputs (packed 8-element vectors)
    input  logic [NUM_COLS*DATA_W-1:0]          din_n,
    input  logic [NUM_ROWS*DATA_W-1:0]          din_w_region_a,
    input  logic [NUM_ROWS*DATA_W-1:0]          din_w_region_b,

    // Mesh streaming outputs (packed 8-element vectors)
    output logic [NUM_COLS*DATA_W-1:0]          dout_s,
    output logic [NUM_ROWS*DATA_W-1:0]          dout_e,

    // Accumulators matrix output (64 PEs * 32-bit = 2048-bit flat vector)
    output logic [NUM_ROWS*NUM_COLS*ACC_W-1:0]  acc_out_flat,

    // Status and arbitration outputs
    output logic [NUM_REGIONS*BW_W-1:0]         bw_alloc,
    output logic [NUM_REGIONS-1:0]              reconfig_urgent,
    output logic [NUM_COLS-1:0]                 region_id_mask,
    output logic [NUM_BANKS-1:0]                scrub_active_bus,
    output logic [NUM_BANKS-1:0]                bank_role_clear_bus,
    output logic [NUM_BANKS*NUM_REGIONS-1:0]    token_grant_bus,
    output logic [NUM_BANKS-1:0]                token_held_bus,
    output logic [NUM_BANKS*REGION_W-1:0]       token_owner_bus,
    output logic [NUM_BANKS*REGION_W-1:0]       bank_owner_bus,
    output logic [NUM_BANKS*2-1:0]              bank_role_tag_bus,
    output logic [NUM_COLS-1:0]                 pe_bank_role_stale_bus
);

    hdf_top #(
        .DATA_W     (DATA_W),
        .ACC_W      (ACC_W),
        .LIFETIME_W (LIFETIME_W),
        .NUM_ROWS   (NUM_ROWS),
        .NUM_COLS   (NUM_COLS),
        .NUM_BANKS  (NUM_BANKS),
        .NUM_REGIONS(NUM_REGIONS),
        .REGION_W   (REGION_W),
        .BW_W       (BW_W),
        .SPLIT_W    (SPLIT_W)
    ) u_hdf_core (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .cfg_split_col          (cfg_split_col),
        .cfg_update_strobe      (cfg_update_strobe),
        .phase_tag              (phase_tag),
        .token_req_A            (token_req_A),
        .token_req_B            (token_req_B),
        .token_release_A        (token_release_A),
        .token_release_B        (token_release_B),
        .role_reassign          (role_reassign),
        .new_region_id_per_bank (new_region_id_per_bank),
        .new_role_per_bank      (new_role_per_bank),
        .dataflow_mode          (dataflow_mode),
        .lifetime_ld            (lifetime_ld),
        .lifetime_init          (lifetime_init),
        .w_ld                   (w_ld),
        .acc_clr                (acc_clr),
        .din_n                  (din_n),
        .din_w_region_a         (din_w_region_a),
        .din_w_region_b         (din_w_region_b),
        .dout_s                 (dout_s),
        .dout_e                 (dout_e),
        .acc_out_flat           (acc_out_flat),
        .bw_alloc               (bw_alloc),
        .reconfig_urgent        (reconfig_urgent),
        .region_id_mask         (region_id_mask),
        .scrub_active_bus       (scrub_active_bus),
        .bank_role_clear_bus    (bank_role_clear_bus),
        .token_grant_bus        (token_grant_bus),
        .token_held_bus         (token_held_bus),
        .token_owner_bus        (token_owner_bus),
        .bank_owner_bus         (bank_owner_bus),
        .bank_role_tag_bus      (bank_role_tag_bus),
        .pe_bank_role_stale_bus (pe_bank_role_stale_bus)
    );

endmodule

