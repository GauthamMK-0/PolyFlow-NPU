// sfa_array.v — 2D Systolic Array Grid with Hardware Boundary Isolation
// Enforces boundary isolation: mesh lines crossing between distinct regions are zeroed.

`timescale 1ns/1ps

module sfa_array #(
    parameter int DATA_W   = 8,
    parameter int ACC_W    = 32,
    parameter int REGION_W = 1,
    parameter int NUM_ROWS = 4,
    parameter int NUM_COLS = 4
) (
    input  logic                                clk,
    input  logic                                rst_n,

    // Boundary data inputs (packed)
    input  logic [NUM_COLS*DATA_W-1:0]          din_n,
    input  logic [NUM_ROWS*DATA_W-1:0]          din_w,
    // Separate direct feed for Region B west boundary when split
    input  logic [NUM_ROWS*DATA_W-1:0]          din_w_region_b,

    // Boundary data outputs (packed)
    output logic [NUM_COLS*DATA_W-1:0]          dout_s,
    output logic [NUM_ROWS*DATA_W-1:0]          dout_e,

    // Full precision accumulator outputs for all PEs (packed flat: [row*NUM_COLS + col])
    output logic [NUM_ROWS*NUM_COLS*ACC_W-1:0]  acc_out_flat,

    // Region configuration & boundary control
    input  logic [NUM_COLS-1:0]                 region_id_mask,
    input  logic [NUM_COLS-1:0]                 region_reassign_bus,
    output logic [NUM_COLS-1:0]                 pe_bank_role_stale,
    input  logic [NUM_COLS-1:0]                 pe_bank_role_clear,

    // Per-region control signals (Region A: bit 0, Region B: bit 1)
    input  logic [1:0]                          w_ld,
    input  logic [1:0]                          acc_clr,
    input  logic [1:0]                          compute_en
);

    /* verilator lint_off UNOPTFLAT */
    wire [DATA_W-1:0] mesh_n [NUM_ROWS-1:0][NUM_COLS-1:0];
    wire [DATA_W-1:0] mesh_w [NUM_ROWS-1:0][NUM_COLS-1:0];
    wire [DATA_W-1:0] mesh_s [NUM_ROWS-1:0][NUM_COLS-1:0];
    wire [DATA_W-1:0] mesh_e [NUM_ROWS-1:0][NUM_COLS-1:0];
    /* verilator lint_on UNOPTFLAT */

    // North inputs: Row 0 from external din_n; row r from row r-1
    for (genvar c = 0; c < NUM_COLS; c++) begin : gen_north_in
        assign mesh_n[0][c] = din_n[c*DATA_W +: DATA_W];
        for (genvar r = 1; r < NUM_ROWS; r++) begin : gen_north_inner
            assign mesh_n[r][c] = mesh_s[r-1][c];
        end
    end

    // West inputs with Boundary Isolation:
    // Col 0 always receives external din_w
    // Col c receives mesh_e from col c-1 UNLESS crossed region boundary (region_id_mask[c] != region_id_mask[c-1])
    // If boundary is crossed, col c receives din_w_region_b for Region B!
    for (genvar r = 0; r < NUM_ROWS; r++) begin : gen_west_in
        assign mesh_w[r][0] = din_w[r*DATA_W +: DATA_W];
        for (genvar c = 1; c < NUM_COLS; c++) begin : gen_west_inner
            assign mesh_w[r][c] = (region_id_mask[c] != region_id_mask[c-1]) ?
                                  din_w_region_b[r*DATA_W +: DATA_W] : mesh_e[r][c-1];
        end
    end

    // Wire per-column stale flag from row 0 PEs
    wire [NUM_COLS-1:0] col_stale;
    assign pe_bank_role_stale = col_stale;

    // PE Instantiations
    for (genvar r = 0; r < NUM_ROWS; r++) begin : gen_pe_row
        for (genvar c = 0; c < NUM_COLS; c++) begin : gen_pe_col
            wire [ACC_W-1:0] pe_acc;
            /* verilator lint_off UNUSEDSIGNAL */
            wire             pe_stale;
            /* verilator lint_on UNUSEDSIGNAL */
            wire             reg_id = region_id_mask[c];

            sfa_pe #(
                .DATA_W(DATA_W),
                .ACC_W(ACC_W),
                .REGION_W(REGION_W)
            ) u_pe (
                .clk            (clk),
                .rst_n          (rst_n),
                .din_n          (mesh_n[r][c]),
                .din_w          (mesh_w[r][c]),
                .dout_s         (mesh_s[r][c]),
                .dout_e         (mesh_e[r][c]),
                .acc_out        (pe_acc),
                .region_id      (reg_id),
                .region_reassign(region_reassign_bus[c]),
                .bank_role_stale(pe_stale),
                .bank_role_clear(pe_bank_role_clear[c]),
                .w_ld           (w_ld[reg_id]),
                .acc_clr        (acc_clr[reg_id]),
                .compute_en     (compute_en[reg_id])
            );

            assign acc_out_flat[(r*NUM_COLS + c)*ACC_W +: ACC_W] = pe_acc;

            if (r == 0) begin : gen_col_stale
                assign col_stale[c] = pe_stale;
            end
        end
    end

    // External outputs
    for (genvar c = 0; c < NUM_COLS; c++) begin : gen_ext_col_out
        assign dout_s[c*DATA_W +: DATA_W] = mesh_s[NUM_ROWS-1][c];
    end

    for (genvar r = 0; r < NUM_ROWS; r++) begin : gen_ext_row_out
        assign dout_e[r*DATA_W +: DATA_W] = mesh_e[r][NUM_COLS-1];
    end

endmodule
