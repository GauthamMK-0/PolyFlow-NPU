// dfs_top_8x8.sv — Dedicated 8x8 Scaled Pod for Single-Tenant Dataflow Switching
// PolyFlow-NPU: 64 Processing Elements with Two-Stage Pipelined Carry-Save Accumulation

`timescale 1ns/1ps

module dfs_top_8x8 #(
    parameter int DATA_W   = 8,
    parameter int ACC_W    = 32,
    parameter int NUM_ROWS = 8,
    parameter int NUM_COLS = 8
) (
    input  logic                                clk,
    input  logic                                rst_n,

    // Tile dispatch & control interface
    input  logic [1:0]                          cfg_dataflow_mode, // 00=WS, 01=OS, 10=IS
    input  logic                                tile_w_ld,         // Preload pulse
    input  logic                                tile_acc_clr,      // Clear accumulators
    input  logic                                tile_compute_en,   // Compute enable

    // Primary streaming interfaces (packed)
    input  logic [NUM_COLS*ACC_W-1:0]           din_n,
    input  logic [NUM_ROWS*DATA_W-1:0]          din_w,
    output logic [NUM_COLS*ACC_W-1:0]           dout_s,
    output logic [NUM_ROWS*DATA_W-1:0]          dout_e,

    // Complete 8x8 accumulator matrix output (64 PEs * 32-bit = 2048-bit flat vector)
    output logic [NUM_ROWS*NUM_COLS*ACC_W-1:0]  acc_out_flat
);

    dfs_top #(
        .DATA_W  (DATA_W),
        .ACC_W   (ACC_W),
        .NUM_ROWS(NUM_ROWS),
        .NUM_COLS(NUM_COLS)
    ) u_dfs_core (
        .clk              (clk),
        .rst_n            (rst_n),
        .cfg_dataflow_mode(cfg_dataflow_mode),
        .tile_w_ld        (tile_w_ld),
        .tile_acc_clr     (tile_acc_clr),
        .tile_compute_en  (tile_compute_en),
        .din_n            (din_n),
        .din_w            (din_w),
        .dout_s           (dout_s),
        .dout_e           (dout_e),
        .acc_out_flat     (acc_out_flat)
    );

endmodule

