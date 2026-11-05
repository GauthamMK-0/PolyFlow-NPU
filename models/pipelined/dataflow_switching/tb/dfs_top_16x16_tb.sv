// dfs_top_16x16_tb.sv — SystemVerilog Testbench for 16x16 Scaled Dataflow Switching Pod
// PolyFlow-NPU: 256 Processing Elements verification across WS, OS, and IS modes.

`timescale 1ns/1ps

module dfs_top_16x16_tb;

    localparam int DATA_W   = 8;
    localparam int ACC_W    = 32;
    localparam int NUM_ROWS = 16;
    localparam int NUM_COLS = 16;

    logic clk;
    logic rst_n;

    logic [1:0]                         cfg_dataflow_mode;
    logic                               tile_w_ld;
    logic                               tile_acc_clr;
    logic                               tile_compute_en;

    logic [NUM_COLS*ACC_W-1:0]         din_n;
    logic [NUM_ROWS*DATA_W-1:0]         din_w;
    /* verilator lint_off UNUSEDSIGNAL */
    wire  [NUM_COLS*ACC_W-1:0]         dout_s;
    wire  [NUM_ROWS*DATA_W-1:0]         dout_e;
    /* verilator lint_on UNUSEDSIGNAL */
    wire  [NUM_ROWS*NUM_COLS*ACC_W-1:0] acc_out_flat;

    int error_count = 0;

    function automatic logic signed [ACC_W-1:0] get_pe_acc(int r, int c);
        return acc_out_flat[(r*NUM_COLS + c)*ACC_W +: ACC_W];
    endfunction

    task automatic set_din_n(int c, logic [ACC_W-1:0] val);
        din_n[c*ACC_W +: ACC_W] = val;
    endtask

    task automatic set_din_w(int r, logic [DATA_W-1:0] val);
        din_w[r*DATA_W +: DATA_W] = val;
    endtask

    dfs_top_16x16 #(
        .DATA_W  (DATA_W),
        .ACC_W   (ACC_W),
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

    task automatic step_clk();
        @(posedge clk);
        #1;
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

    logic signed [ACC_W-1:0] exp_val;
    int k_idx_c;
    int k_idx_r;
    int k_w;

    initial begin
        $display("================================================================");
        $display(" [TESTSUITE] Starting 16x16 Scaled Dataflow Switching Pod Tests");
        $display("================================================================");

        reset_dut();

        // TEST 1: Weight-Stationary (WS) Mode
        $display("\n--- [TEST 1] 16x16 WS Mode Execution ---");
        cfg_dataflow_mode = 2'b00;
        tile_acc_clr      = 1;
        step_clk();
        tile_acc_clr      = 0;

        // Preload stationary weights: shift West-to-East across all NUM_COLS columns
        tile_w_ld = 1;
        for (int step = NUM_COLS - 1; step >= 0; step--) begin
            for (int r = 0; r < NUM_ROWS; r++) begin
                set_din_w(r, 8'd5 + step[7:0]);
            end
            step_clk();
        end
        tile_w_ld = 0;
        din_w     = '0;

        // Stream activations through West: (r + 1) * ((5 + c) * 3)
        tile_compute_en = 1;
        for (int r = 0; r < NUM_ROWS; r++) set_din_w(r, 8'd3);
        repeat (NUM_ROWS + NUM_COLS + 2) step_clk();
        tile_compute_en = 0;
        din_w           = '0;
        step_clk(); // Drain pipeline stage

        $display("16x16 WS Mode: PE[0][0] = %0d, PE[15][15] = %0d (Expected: %0d, %0d)",
                 get_pe_acc(0,0), get_pe_acc(15,15), 1*3*(5+0), NUM_ROWS*3*(5+15));
        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < NUM_COLS; c++) begin
                exp_val = (r + 1) * 32'd3 * (32'd5 + c);
                if (get_pe_acc(r, c) !== exp_val) begin
                    $display("ERROR: 16x16 WS Mode mismatch at PE[%0d][%0d]!", r, c);
                    error_count++;
                end
            end
        end
        if (error_count == 0) begin
            $display("PASS: 16x16 WS Mode verified successfully across all 256 PEs.");
        end

        // TEST 2: Output-Stationary (OS) Mode
        $display("\n--- [TEST 2] 16x16 OS Mode Execution ---");
        din_n           = '0;
        din_w           = '0;
        tile_compute_en = 0;
        repeat (NUM_ROWS + NUM_COLS + 2) step_clk();

        tile_acc_clr      = 1;
        cfg_dataflow_mode = 2'b01;
        step_clk();
        tile_acc_clr      = 0;

        // Stream 3 vectors with 2D systolic skew: (4*7 + 2*6 + 3*5 = 55)
        tile_compute_en = 1;
        for (int t = 0; t < 3 + NUM_ROWS + NUM_COLS + 2; t++) begin
            for (int c = 0; c < NUM_COLS; c++) begin
                k_idx_c = t - c;
                if (k_idx_c == 0)      set_din_n(c, 32'd4);
                else if (k_idx_c == 1) set_din_n(c, 32'd2);
                else if (k_idx_c == 2) set_din_n(c, 32'd3);
                else                   set_din_n(c, 32'd0);
            end
            for (int r = 0; r < NUM_ROWS; r++) begin
                k_idx_r = t - r;
                if (k_idx_r == 0)      set_din_w(r, 8'd7);
                else if (k_idx_r == 1) set_din_w(r, 8'd6);
                else if (k_idx_r == 2) set_din_w(r, 8'd5);
                else                   set_din_w(r, 8'd0);
            end
            step_clk();
        end
        tile_compute_en = 0;
        din_n           = '0;
        din_w           = '0;
        repeat (NUM_ROWS + NUM_COLS + 2) step_clk();

        $display("16x16 OS Mode: Verifying all PEs across 16x16 grid (Expected: 55)");
        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < NUM_COLS; c++) begin
                if (get_pe_acc(r, c) !== 32'd55) begin
                    $display("ERROR: 16x16 OS Mode mismatch at PE[%0d][%0d]: %0d (Expected: 55)!", r, c, get_pe_acc(r, c));
                    error_count++;
                end
            end
        end
        if (error_count == 0) begin
            $display("PASS: 16x16 OS Mode verified successfully across all 256 PEs.");
        end

        // TEST 3: Input-Stationary (IS) Mode
        $display("\n--- [TEST 3] 16x16 IS Mode Execution ---");
        din_n           = '0;
        din_w           = '0;
        tile_compute_en = 0;
        repeat (NUM_ROWS + NUM_COLS + 2) step_clk();

        tile_acc_clr      = 1;
        cfg_dataflow_mode = 2'b10;
        step_clk();
        tile_acc_clr      = 0;

        // Preload activation = 6 shifting North-to-South across all 16 rows
        tile_w_ld = 1;
        for (int step = NUM_ROWS - 1; step >= 0; step--) begin
            for (int c = 0; c < NUM_COLS; c++) set_din_n(c, 32'd6);
            step_clk();
        end
        tile_w_ld = 0;
        din_n     = '0;

        // Stream weights = 4 for 3 cycles from West with systolic propagation: 3 * (6 * 4) = 72
        tile_compute_en = 1;
        for (int t = 0; t < 3 + NUM_COLS + NUM_ROWS + 2; t++) begin
            for (int r = 0; r < NUM_ROWS; r++) begin
                k_w = t - r;
                if (k_w >= 0 && k_w < 3) set_din_w(r, 8'd4);
                else                     set_din_w(r, 8'd0);
            end
            step_clk();
        end
        tile_compute_en = 0;
        din_w           = '0;
        repeat (NUM_ROWS + NUM_COLS + 2) step_clk();

        $display("16x16 IS Mode: Verifying all PEs across 16x16 grid (Expected: 72)");
        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < NUM_COLS; c++) begin
                if (get_pe_acc(r, c) !== 32'd72) begin
                    $display("ERROR: 16x16 IS Mode mismatch at PE[%0d][%0d]: %0d (Expected: 72)!", r, c, get_pe_acc(r, c));
                    error_count++;
                end
            end
        end
        if (error_count == 0) begin
            $display("PASS: 16x16 IS Mode verified successfully across all 256 PEs.");
        end

        // Summary
        $display("\n================================================================");
        if (error_count == 0) begin
            $display(" [SUCCESS] ALL 16x16 DATAFLOW SWITCHING TESTS PASSED (Errors: 0)");
            $display("================================================================");
            $finish(0);
        end else begin
            $display(" [FAILED] 16x16 DATAFLOW SWITCHING TESTS ENCOUNTERED %0d ERRORS", error_count);
            $display("================================================================");
            $finish(1);
        end
    end

endmodule

