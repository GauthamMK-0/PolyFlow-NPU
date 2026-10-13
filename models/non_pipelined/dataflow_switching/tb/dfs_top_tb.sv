// dfs_top_tb.sv — SystemVerilog Testbench for Single-Tenant Dataflow Switching Model
// Verifies sequential execution across WS (Conv/FC), OS (Attention), and IS (Depthwise Conv) modes.

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

    // Clock generator (100 MHz) with non-blocking assignment
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

    initial begin
        $display("================================================================");
        $display(" [TESTSUITE] Starting Dataflow Switching Model (Model 1) Tests");
        $display("================================================================");

        reset_dut();

        // -------------------------------------------------------------
        // TEST 1: Weight-Stationary (WS) Mode (Conv / FC Layer)
        // -------------------------------------------------------------
        $display("\n--- [TEST 1] Weight-Stationary (WS) Mode Execution ---");
        cfg_dataflow_mode = 2'b00; // WS mode
        tile_acc_clr      = 1;
        step_clk();
        tile_acc_clr      = 0;

        // Step 1.1: Preload stationary weights from West into row 0
        tile_w_ld = 1;
        for (int r = 0; r < NUM_ROWS; r++) begin
            set_din_w(r, 8'd5); // Stationary weight = 5
        end
        step_clk();
        tile_w_ld = 0;

        // Step 1.2: Stream activation inputs through West port (combinational product)
        tile_compute_en = 1;
        for (int r = 0; r < NUM_ROWS; r++) begin
            set_din_w(r, 8'd3); // Activation = 3
        end
        step_clk(); // Combinational product: 5 * 3 = 15

        $display("WS Mode (Combinational): PE[0][0] Product = %0d (Expected: 15)", get_pe_acc(0,0));
        if (get_pe_acc(0,0) !== 32'd15) begin
            $display("ERROR: WS Mode calculation mismatch!");
            error_count++;
        end else begin
            $display("PASS: WS Mode combinational MAC verified successfully.");
        end
        tile_compute_en = 0;

        // -------------------------------------------------------------
        // TEST 2: Output-Stationary (OS) Mode (Attention Layer Q*K^T)
        // -------------------------------------------------------------
        $display("\n--- [TEST 2] Output-Stationary (OS) Mode Execution ---");
        tile_acc_clr      = 1;
        cfg_dataflow_mode = 2'b01; // OS mode
        step_clk();
        tile_acc_clr      = 0;

        // In OS mode, operands stream simultaneously from North (Q) and West (K)
        tile_compute_en = 1;
        // Cycle 1: Q=4, K=7 -> prod = 28
        for (int c = 0; c < NUM_COLS; c++) set_din_n(c, 8'd4);
        for (int r = 0; r < NUM_ROWS; r++) set_din_w(r, 8'd7);
        step_clk();

        $display("OS Mode (Cycle 1): PE[0][0] Product = %0d (Expected: 28)", get_pe_acc(0,0));
        if (get_pe_acc(0,0) !== 32'd28) begin
            $display("ERROR: OS Mode calculation mismatch!");
            error_count++;
        end else begin
            $display("PASS: OS Mode combinational MAC verified successfully.");
        end

        // Cycle 2: Q=2, K=6 -> prod = 12
        for (int c = 0; c < NUM_COLS; c++) set_din_n(c, 8'd2);
        for (int r = 0; r < NUM_ROWS; r++) set_din_w(r, 8'd6);
        step_clk();

        if (get_pe_acc(0,0) !== 32'd12) begin
            $display("ERROR: OS Mode cycle 2 mismatch!");
            error_count++;
        end
        tile_compute_en = 0;

        // -------------------------------------------------------------
        // TEST 3: Input-Stationary (IS) Mode (Depthwise Conv)
        // -------------------------------------------------------------
        $display("\n--- [TEST 3] Input-Stationary (IS) Mode Execution ---");
        tile_acc_clr      = 1;
        cfg_dataflow_mode = 2'b10; // IS mode
        step_clk();
        tile_acc_clr      = 0;

        // Preload activation from North
        tile_w_ld = 1;
        for (int c = 0; c < NUM_COLS; c++) set_din_n(c, 8'd6); // Stationary activation = 6
        step_clk();
        tile_w_ld = 0;

        // Stream weights from West: weight = 4 -> instantaneous prod = 24
        tile_compute_en = 1;
        for (int r = 0; r < NUM_ROWS; r++) set_din_w(r, 8'd4);
        step_clk(); // 6 * 4 = 24

        $display("IS Mode (Combinational): PE[0][0] Product = %0d (Expected: 24)", get_pe_acc(0,0));
        if (get_pe_acc(0,0) !== 32'd24) begin
            $display("ERROR: IS Mode calculation mismatch!");
            error_count++;
        end else begin
            $display("PASS: IS Mode combinational MAC verified successfully.");
        end
        tile_compute_en = 0;

        // -------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------
        $display("\n================================================================");
        if (error_count == 0) begin
            $display(" [SUCCESS] ALL DATAFLOW SWITCHING TESTS PASSED (Errors: 0)");
            $display("================================================================");
            $finish(0);
        end else begin
            $display(" [FAILED] DATAFLOW SWITCHING TESTS ENCOUNTERED %0d ERRORS", error_count);
            $display("================================================================");
            $finish(1);
        end
    end

endmodule
