// hdf_top.v — Top-Level Pod for Heterogeneous Fission Architecture (PolyFlow-NPU)
// Unifies spatial multi-tenancy with independent per-region dataflow switching (WS / OS / IS).

`timescale 1ns/1ps

module hdf_top #(
    parameter int DATA_W      = 8,
    parameter int ACC_W       = 32,
    parameter int LIFETIME_W  = 4,
    parameter int NUM_ROWS    = 4,
    parameter int NUM_COLS    = 4,
    parameter int NUM_BANKS   = 2,
    parameter int NUM_REGIONS = 2,
    parameter int REGION_W    = 1,
    parameter int BW_W        = 8
) (
    input  logic                                clk,
    input  logic                                rst_n,

    // Dispatch-Time Spatial Fission Configuration
    input  logic [3:0]                          cfg_split_col,
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

    // Mesh streaming data inputs (packed)
    input  logic [NUM_COLS*DATA_W-1:0]          din_n,
    input  logic [NUM_ROWS*DATA_W-1:0]          din_w_region_a,
    input  logic [NUM_ROWS*DATA_W-1:0]          din_w_region_b,

    // Mesh streaming outputs (packed)
    output logic [NUM_COLS*DATA_W-1:0]          dout_s,
    output logic [NUM_ROWS*DATA_W-1:0]          dout_e,

    // Complete accumulator output (packed flat: [row*NUM_COLS + col])
    output logic [NUM_ROWS*NUM_COLS*ACC_W-1:0]  acc_out_flat,

    // Status & arbitration outputs
    output logic [NUM_REGIONS*BW_W-1:0]         bw_alloc,
    output logic [NUM_REGIONS-1:0]              reconfig_urgent,
    output logic [NUM_COLS-1:0]                 region_id_mask,
    output logic [NUM_BANKS-1:0]                scrub_active_bus,
    output logic [NUM_BANKS-1:0]                bank_role_clear_bus
);

    wire [NUM_COLS-1:0] region_reassign_bus;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [NUM_COLS-1:0] pe_bank_role_stale;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [NUM_COLS-1:0] pe_bank_role_clear;

    // Fission Decoder
    hdf_fission_decoder #(
        .NUM_COLS(NUM_COLS)
    ) u_fission_dec (
        .clk                (clk),
        .rst_n              (rst_n),
        .cfg_split_col      (cfg_split_col),
        .cfg_update_strobe  (cfg_update_strobe),
        .region_id_mask     (region_id_mask),
        .region_reassign_bus(region_reassign_bus)
    );

    // EPPA Arbiter
    eppa_arbiter #(
        .NUM_REGIONS(NUM_REGIONS),
        .BW_W(BW_W)
    ) u_eppa (
        .clk            (clk),
        .rst_n          (rst_n),
        .phase_tag      (phase_tag),
        .bw_alloc       (bw_alloc),
        .reconfig_urgent(reconfig_urgent)
    );

    // Per-Bank OTP & Scrub Controllers
    for (genvar b = 0; b < NUM_BANKS; b++) begin : gen_bank_ctrl
        wire scrub_wire;
        wire clr_wire;
        wire [NUM_REGIONS-1:0] req_bank = {token_req_B[b], token_req_A[b]};
        wire [NUM_REGIONS-1:0] rel_bank = {token_release_B[b], token_release_A[b]};
        /* verilator lint_off UNUSEDSIGNAL */
        wire [REGION_W-1:0]    token_owner;
        wire                   token_held;
        wire [NUM_REGIONS-1:0] grant;
        wire [REGION_W-1:0]    reg_owner;
        wire [1:0]             role_tag_wire;
        /* verilator lint_on UNUSEDSIGNAL */

        otp_token_fsm #(
            .NUM_REGIONS(NUM_REGIONS),
            .REGION_W(REGION_W)
        ) u_otp (
            .clk          (clk),
            .rst_n        (rst_n),
            .token_req    (req_bank),
            .token_release(rel_bank),
            .scrub_active (scrub_wire),
            .token_owner  (token_owner),
            .token_held   (token_held),
            .grant        (grant)
        );

        pod_bank_scrub #(
            .REGION_W(REGION_W)
        ) u_scrub (
            .clk            (clk),
            .rst_n          (rst_n),
            .role_reassign  (role_reassign[b]),
            .new_region_id  (new_region_id_per_bank[b]),
            .new_role       (new_role_per_bank[2*b +: 2]),
            .scrub_active   (scrub_wire),
            .bank_role_clear(clr_wire),
            .region_owner   (reg_owner),
            .role_tag       (role_tag_wire)
        );

        assign scrub_active_bus[b]    = scrub_wire;
        assign bank_role_clear_bus[b] = clr_wire;
    end

    // Broadcast clear signals to PEs based on region
    always_comb begin
        for (int c = 0; c < NUM_COLS; c++) begin
            if (region_id_mask[c]) begin
                pe_bank_role_clear[c] = bank_role_clear_bus[1];
            end else begin
                pe_bank_role_clear[c] = bank_role_clear_bus[0];
            end
        end
    end

    // 2D Array Grid with Dynamic Boundary Isolation & Independent Per-Region Dataflows
    hdf_array_grid #(
        .DATA_W     (DATA_W),
        .ACC_W      (ACC_W),
        .LIFETIME_W (LIFETIME_W),
        .REGION_W   (REGION_W),
        .NUM_REGIONS(NUM_REGIONS),
        .NUM_ROWS   (NUM_ROWS),
        .NUM_COLS   (NUM_COLS)
    ) u_array (
        .clk                (clk),
        .rst_n              (rst_n),
        .din_n              (din_n),
        .din_w_region_a     (din_w_region_a),
        .din_w_region_b     (din_w_region_b),
        .dout_s             (dout_s),
        .dout_e             (dout_e),
        .acc_out_flat       (acc_out_flat),
        .region_id_mask     (region_id_mask),
        .region_reassign_bus(region_reassign_bus),
        .pe_bank_role_stale (pe_bank_role_stale),
        .pe_bank_role_clear (pe_bank_role_clear),
        .dataflow_mode      (dataflow_mode),
        .lifetime_ld        (lifetime_ld),
        .lifetime_init      (lifetime_init),
        .w_ld               (w_ld),
        .acc_clr            (acc_clr)
    );

endmodule
