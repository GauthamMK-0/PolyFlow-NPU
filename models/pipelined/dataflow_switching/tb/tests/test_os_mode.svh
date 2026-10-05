// test_os_mode.svh — TEST 2: Output-Stationary (OS) Mode Execution
// Included in dfs_top_tb.sv

task automatic run_test_os_mode();
    $display("\n--- [TEST 2] Output-Stationary (OS) Mode Execution ---");
    // Clear accumulators for new tile
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

    // Cycle 2: Q=2, K=6 -> prod = 12 -> acc = 28 + 12 = 40
    for (int c = 0; c < NUM_COLS; c++) set_din_n(c, 8'd2);
    for (int r = 0; r < NUM_ROWS; r++) set_din_w(r, 8'd6);
    step_clk();

    // Cycle 3: Q=3, K=5 -> prod = 15 -> acc = 40 + 15 = 55
    for (int c = 0; c < NUM_COLS; c++) set_din_n(c, 8'd3);
    for (int r = 0; r < NUM_ROWS; r++) set_din_w(r, 8'd5);
    step_clk();
    tile_compute_en = 0;

    $display("OS Mode: PE[0][0] Accumulator = %0d (Expected: 55)", get_pe_acc(0,0));
    if (get_pe_acc(0,0) !== 32'd55) begin
        $display("ERROR: OS Mode calculation mismatch!");
        error_count++;
    end else begin
        $display("PASS: OS Mode verified successfully.");
    end
endtask
