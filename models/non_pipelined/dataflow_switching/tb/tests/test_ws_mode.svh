// test_ws_mode.svh — TEST 1: Weight-Stationary (WS) Mode Execution
// Included in dfs_top_tb.sv (Non-Pipelined Combinational)

task automatic run_test_ws_mode();
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
endtask
