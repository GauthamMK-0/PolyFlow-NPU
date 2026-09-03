// hdf_array_grid.v — 2D Systolic Array Grid with Dynamic Boundary Isolation & Heterogeneous Dataflows
// Allows Region A and Region B to execute distinct dataflows simultaneously on the same physical mesh.

`timescale 1ns/1ps

module hdf_array_grid #(
    parameter int DATA_W      = 8,
    parameter int ACC_W       = 32,
    parameter int LIFETIME_W  = 4,
    parameter int REGION_W    = 1,
    parameter int NUM_REGIONS = 2,
    parameter int NUM_ROWS    = 4,
    parameter int NUM_COLS    = 4
) (
    input  logic                                clk,
    input  logic                                rst_n,

    // Boundary data inputs (packed)
    input  logic [NUM_COLS*DATA_W-1:0]          din_n,
    input  logic [NUM_ROWS*DATA_W-1:0]          din_w_region_a,
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

    // Per-Region Heterogeneous Dataflow Selection (packed: [2*r +: 2])
    input  logic [2*NUM_REGIONS-1:0]            dataflow_mode,

    // Per-Region Lifetime & Execution control (packed)
    input  logic [NUM_REGIONS-1:0]              lifetime_ld,
    input  logic [NUM_REGIONS*LIFETIME_W-1:0]   lifetime_init,
    input  logic [NUM_REGIONS-1:0]              w_ld,
    input  logic [NUM_REGIONS-1:0]              acc_clr
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
    // Col 0 receives din_w_region_a
    // Col c receives din_w_region_b if crossing boundary (region_id_mask[c] != region_id_mask[c-1]), else mesh_e from left
    for (genvar r = 0; r < NUM_ROWS; r++) begin : gen_west_in
        assign mesh_w[r][0] = din_w_region_a[r*DATA_W +: DATA_W];
        for (genvar c = 1; c < NUM_COLS; c++) begin : gen_west_inner
            assign mesh_w[r][c] = (region_id_mask[c] != region_id_mask[c-1]) ?
                                  din_w_region_b[r*DATA_W +: DATA_W] : mesh_e[r][c-1];
        end
    end

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

            hdf_pe #(
                .DATA_W    (DATA_W),
                .ACC_W     (ACC_W),
                .LIFETIME_W(LIFETIME_W),
                .REGION_W  (REGION_W)
            ) u_pe (
                .clk            (clk),
                .rst_n          (rst_n),
                .din_n          (mesh_n[r][c]),
                .din_w          (mesh_w[r][c]),
                .dout_s         (mesh_s[r][c]),
                .dout_e         (mesh_e[r][c]),
                .acc_out        (pe_acc),
                .dataflow_mode  (dataflow_mode[reg_id*2 +: 2]), // Per-region independent dataflow mode!
                .region_id      (reg_id),
                .region_reassign(region_reassign_bus[c]),
                .lifetime_ld    (lifetime_ld[reg_id]),
                .lifetime_init  (lifetime_init[reg_id*LIFETIME_W +: LIFETIME_W]),
                .bank_role_stale(pe_stale),
                .bank_role_clear(pe_bank_role_clear[c]),
                .w_ld           (w_ld[reg_id]),
                .acc_clr        (acc_clr[reg_id])
            );

            assign acc_out_flat[(r*NUM_COLS + c)*ACC_W +: ACC_W] = pe_acc;

            if (r == 0) begin : gen_col_stale
                assign col_stale[c] = pe_stale;
            end
        end
    end

    // External boundary outputs
    for (genvar c = 0; c < NUM_COLS; c++) begin : gen_ext_col_out
        assign dout_s[c*DATA_W +: DATA_W] = mesh_s[NUM_ROWS-1][c];
    end

    for (genvar r = 0; r < NUM_ROWS; r++) begin : gen_ext_row_out
        assign dout_e[r*DATA_W +: DATA_W] = mesh_e[r][NUM_COLS-1];
    end

endmodule
