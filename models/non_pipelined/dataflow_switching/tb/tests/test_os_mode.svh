// test_os_mode.svh — TEST 2: Output-Stationary (OS) Mode Execution
// Included in dfs_top_tb.sv (Non-Pipelined Combinational)

task automatic run_test_os_mode();
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
    tile_compute_en = 0;
endtask
