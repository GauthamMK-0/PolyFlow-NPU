// test_is_mode.svh — TEST 3: Input-Stationary (IS) Mode Execution
// Included in dfs_top_tb.sv (Non-Pipelined Combinational)

task automatic run_test_is_mode();
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

    // Stream weights from West (combinational product)
    tile_compute_en = 1;
    for (int r = 0; r < NUM_ROWS; r++) set_din_w(r, 8'd4); // weight = 4
    step_clk(); // 6 * 4 = 24

    $display("IS Mode (Combinational): PE[0][0] Product = %0d (Expected: 24)", get_pe_acc(0,0));
    if (get_pe_acc(0,0) !== 32'd24) begin
        $display("ERROR: IS Mode calculation mismatch!");
        error_count++;
    end else begin
        $display("PASS: IS Mode combinational MAC verified successfully.");
    end
    tile_compute_en = 0;
endtask
