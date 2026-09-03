// dfs_array.v — 2D Systolic Array Grid for Single-Tenant Dataflow Switching
// Interconnects PEs in a clean 2D mesh (North->South and West->East).

`timescale 1ns/1ps

module dfs_array #(
    parameter int DATA_W   = 8,
    parameter int ACC_W    = 32,
    parameter int NUM_ROWS = 4,
    parameter int NUM_COLS = 4
) (
    input  logic                                clk,
    input  logic                                rst_n,

    // Boundary data inputs (packed vectors)
    input  logic [NUM_COLS*DATA_W-1:0]          din_n, // North streaming inputs
    input  logic [NUM_ROWS*DATA_W-1:0]          din_w, // West streaming inputs

    // Boundary data outputs (packed vectors)
    output logic [NUM_COLS*DATA_W-1:0]          dout_s, // South streaming outputs
    output logic [NUM_ROWS*DATA_W-1:0]          dout_e, // East streaming outputs

    // Full precision accumulator outputs for all PEs (flattened: [row*NUM_COLS + col])
    output logic [NUM_ROWS*NUM_COLS*ACC_W-1:0]  acc_out_flat,

    // Global control signals
    input  logic [1:0]                          dataflow_mode,
    input  logic                                w_ld,
    input  logic                                acc_clr,
    input  logic                                compute_en
);

    // Internal mesh wiring
    wire [DATA_W-1:0] mesh_n [NUM_ROWS-1:0][NUM_COLS-1:0];
    wire [DATA_W-1:0] mesh_w [NUM_ROWS-1:0][NUM_COLS-1:0];
    wire [DATA_W-1:0] mesh_s [NUM_ROWS-1:0][NUM_COLS-1:0];
    wire [DATA_W-1:0] mesh_e [NUM_ROWS-1:0][NUM_COLS-1:0];

    // North inputs: Row 0 from external din_n; row r from row r-1
    for (genvar c = 0; c < NUM_COLS; c++) begin : gen_north_in
        assign mesh_n[0][c] = din_n[c*DATA_W +: DATA_W];
        for (genvar r = 1; r < NUM_ROWS; r++) begin : gen_north_inner
            assign mesh_n[r][c] = mesh_s[r-1][c];
        end
    end

    // West inputs: Col 0 from external din_w; col c from col c-1
    for (genvar r = 0; r < NUM_ROWS; r++) begin : gen_west_in
        assign mesh_w[r][0] = din_w[r*DATA_W +: DATA_W];
        for (genvar c = 1; c < NUM_COLS; c++) begin : gen_west_inner
            assign mesh_w[r][c] = mesh_e[r][c-1];
        end
    end

    // PE Instantiations
    for (genvar r = 0; r < NUM_ROWS; r++) begin : gen_pe_row
        for (genvar c = 0; c < NUM_COLS; c++) begin : gen_pe_col
            wire [ACC_W-1:0] pe_acc;

            dfs_pe #(
                .DATA_W(DATA_W),
                .ACC_W(ACC_W)
            ) u_pe (
                .clk          (clk),
                .rst_n        (rst_n),
                .din_n        (mesh_n[r][c]),
                .din_w        (mesh_w[r][c]),
                .dout_s       (mesh_s[r][c]),
                .dout_e       (mesh_e[r][c]),
                .acc_out      (pe_acc),
                .dataflow_mode(dataflow_mode),
                .w_ld         (w_ld),
                .acc_clr      (acc_clr),
                .compute_en   (compute_en)
            );

            assign acc_out_flat[(r*NUM_COLS + c)*ACC_W +: ACC_W] = pe_acc;
        end
    end

    // External outputs from array boundaries
    for (genvar c = 0; c < NUM_COLS; c++) begin : gen_ext_col_out
        assign dout_s[c*DATA_W +: DATA_W] = mesh_s[NUM_ROWS-1][c];
    end

    for (genvar r = 0; r < NUM_ROWS; r++) begin : gen_ext_row_out
        assign dout_e[r*DATA_W +: DATA_W] = mesh_e[r][NUM_COLS-1];
    end

endmodule
