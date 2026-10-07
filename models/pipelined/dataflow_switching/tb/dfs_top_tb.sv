// dfs_top_tb.sv — SystemVerilog Hybrid Harness for Single-Tenant Dataflow Switching Model
// Modular test dispatcher compatible with both Verilator and Cadence Xcelium.

`timescale 1ns/1ps

module dfs_top_tb;

    localparam int DATA_W   = 8;
    localparam int ACC_W    = 32;
    localparam int NUM_ROWS = 4;
    localparam int NUM_COLS = 4;

    logic clk;
    logic rst_n;

    logic [1:0]                         cfg_dataflow_mode;
    logic                               tile_w_ld;
    logic                               tile_acc_clr;
    logic                               tile_compute_en;

    logic [NUM_COLS*DATA_W-1:0]         din_n;
    logic [NUM_ROWS*DATA_W-1:0]         din_w;
    /* verilator lint_off UNUSEDSIGNAL */
    wire  [NUM_COLS*DATA_W-1:0]         dout_s;
    wire  [NUM_ROWS*DATA_W-1:0]         dout_e;
    /* verilator lint_on UNUSEDSIGNAL */
    wire  [NUM_ROWS*NUM_COLS*ACC_W-1:0] acc_out_flat;

    int error_count = 0;
    string target_test = "ALL";

    // Helper to read accumulator for PE at [row, col]
    function automatic logic signed [ACC_W-1:0] get_pe_acc(int r, int c);
        return acc_out_flat[(r*NUM_COLS + c)*ACC_W +: ACC_W];
    endfunction

    // Helper to set din_n for column c
    task automatic set_din_n(int c, logic [DATA_W-1:0] val);
        din_n[c*DATA_W +: DATA_W] = val;
    endtask

    // Helper to set din_w for row r
    task automatic set_din_w(int r, logic [DATA_W-1:0] val);
        din_w[r*DATA_W +: DATA_W] = val;
    endtask

    // Instantiate Device Under Test
    dfs_top #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .NUM_ROWS(NUM_ROWS),
        .NUM_COLS(NUM_COLS)
    ) dut (
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

    // Clock generator (100 MHz)
    initial clk = 0;
    always #5 clk <= ~clk;

    // --- Functional Coverage & Monitoring ---
    `include "dfs_coverage_monitor.svh"

    task automatic step_clk();
        @(posedge clk);
        #1;
        sample_coverage();
    endtask

    task automatic reset_dut();
        rst_n             = 0;
        cfg_dataflow_mode = 2'b00;
        tile_w_ld         = 0;
        tile_acc_clr      = 1;
        tile_compute_en   = 0;
        din_n             = '0;
        din_w             = '0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        step_clk();
        tile_acc_clr = 0;
        step_clk();
    endtask

    // --- Modular Test Inclusions (Hybrid Harness Pattern) ---
    `include "tests/test_ws_mode.svh"
    `include "tests/test_os_mode.svh"
    `include "tests/test_is_mode.svh"
    `include "tests/test_corner_compute_gating.svh"
    `include "tests/test_random_stimulus.svh"

    // --- Test Dispatcher & Regression Summary ---
    initial begin
        void'($value$plusargs("TEST=%s", target_test));

        $display("================================================================");
        $display(" [HYBRID HARNESS] Dataflow Switching Model (Model 1)");
        $display(" Target Test Selection: %s", target_test);
        $display("================================================================");

        if (target_test == "ALL" || target_test == "ws") begin
            reset_dut();
            run_test_ws_mode();
        end

        if (target_test == "ALL" || target_test == "os") begin
            reset_dut();
            run_test_os_mode();
        end

        if (target_test == "ALL" || target_test == "is") begin
            reset_dut();
            run_test_is_mode();
        end

        if (target_test == "ALL" || target_test == "gating") begin
            reset_dut();
            run_test_corner_compute_gating();
        end

        if (target_test == "ALL" || target_test == "random") begin
            reset_dut();
            run_test_random_stimulus();
        end

        // Display comprehensive functional coverage report
        print_functional_coverage_report();

        $display("\n================================================================");
        if (error_count == 0) begin
            $display(" [SUCCESS] ALL EXECUTED DATAFLOW SWITCHING TESTS PASSED (Errors: 0)");
            $display("================================================================");
            $finish(0);
        end else begin
            $display(" [FAILED] DATAFLOW SWITCHING TESTS ENCOUNTERED %0d ERRORS", error_count);
            $display("================================================================");
            $finish(1);
        end
    end

endmodule
