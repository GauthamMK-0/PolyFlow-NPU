// test_corner_compute_gating.svh — TEST: Tile Compute Enable Gating & Zero Clamping (Non-Pipelined)
// Verifies that deasserting tile_compute_en clamps combinational outputs to zero.

task automatic run_test_corner_compute_gating();
    $display("\n--- [TEST: CORNER] Tile Compute Enable Gating & Zero Clamping ---");
    cfg_dataflow_mode = 2'b00; // WS mode
    tile_acc_clr      = 1;
    tile_compute_en   = 0;
    step_clk();
    tile_acc_clr      = 0;

    // Preload stationary weight = 5
    tile_w_ld = 1;
    for (int r = 0; r < NUM_ROWS; r++) set_din_w(r, 8'd5);
    step_clk();
    tile_w_ld = 0;

    // Cycle 1: Compute enabled -> product = 5 * 3 = 15
    tile_compute_en = 1;
    for (int r = 0; r < NUM_ROWS; r++) set_din_w(r, 8'd3);
    step_clk();
    $display("Cycle 1 (Active): PE[0][0] Product = %0d (Expected: 15)", get_pe_acc(0,0));
    if (get_pe_acc(0,0) !== 32'd15) begin
        $display("ERROR: Active compute cycle mismatch: %0d", get_pe_acc(0,0));
        error_count++;
    end

    // Cycle 2: Compute disabled -> product MUST clamp to 0
    tile_compute_en = 0;
    for (int r = 0; r < NUM_ROWS; r++) set_din_w(r, 8'd3);
    step_clk();
    $display("Cycle 2 (Gated): PE[0][0] Product = %0d (Expected: 0)", get_pe_acc(0,0));
    if (get_pe_acc(0,0) !== 32'd0) begin
        $display("ERROR: Compute gating failed! Product non-zero while compute_en=0: %0d", get_pe_acc(0,0));
        error_count++;
    end else begin
        $display("PASS: Product cleanly clamped to 0 while compute_en=0.");
    end

    // Cycle 3: Compute re-enabled -> product = 5 * 4 = 20
    tile_compute_en = 1;
    for (int r = 0; r < NUM_ROWS; r++) set_din_w(r, 8'd4);
    step_clk();
    $display("Cycle 3 (Resumed): PE[0][0] Product = %0d (Expected: 20)", get_pe_acc(0,0));
    if (get_pe_acc(0,0) !== 32'd20) begin
        $display("ERROR: Compute resume mismatch: %0d", get_pe_acc(0,0));
        error_count++;
    end else begin
        $display("PASS: Compute resumed cleanly after re-enabling compute_en!");
    end

    tile_compute_en = 0;
endtask
