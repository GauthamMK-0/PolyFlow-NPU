// test_corner_lifetime_expiry.svh — TEST: Tenant Lifetime Expiration & Auto-Clamping (Non-Pipelined)
// Verifies that when a tenant's hardware lifetime expires, PE compute clamps to zero to prevent unbudgeted execution.

task automatic run_test_corner_lifetime_expiry();
    $display("\n--- [TEST: CORNER] Tenant Lifetime Expiration & Auto-Clamping (Non-Pipelined) ---");
    acc_clr = 2'b11;
    dataflow_mode = {2'b00, 2'b00}; // Both regions WS mode
    step_clk();
    acc_clr = 2'b00;

    // Preload stationary weight for Region A
    w_ld[0] = 1'b1;
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd10);
    step_clk();
    w_ld[0] = 1'b0;

    // Load lifetime_cnt = 3 for Region A (gives 2 active combinational cycles after decrement)
    lifetime_ld[0]     = 1'b1;
    lifetime_init[3:0] = 4'd3;
    step_clk();
    lifetime_ld[0]     = 1'b0;

    // Cycle 1: Stream activation 3 -> Combinational product = 10 * 3 = 30
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
    step_clk();
    $display("Cycle 1 (Active): PE[0][0] Product = %0d (Expected: 30)", get_pe_acc(0,0));
    if (get_pe_acc(0,0) !== 32'd30) begin
        $display("ERROR: Cycle 1 product mismatch: %0d", get_pe_acc(0,0));
        error_count++;
    end

    // Cycle 2: Stream activation 3 -> Combinational product = 10 * 3 = 30
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
    step_clk();
    $display("Cycle 2 (Active): PE[0][0] Product = %0d (Expected: 30)", get_pe_acc(0,0));
    if (get_pe_acc(0,0) !== 32'd30) begin
        $display("ERROR: Cycle 2 product mismatch: %0d", get_pe_acc(0,0));
        error_count++;
    end

    // Cycle 3: Lifetime has expired (cnt == 0). Stream activation 3.
    // Product should clamp to ZERO because mac_en is deasserted.
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
    step_clk();
    $display("Cycle 3 (Expired): PE[0][0] Product = %0d (Expected: 0)", get_pe_acc(0,0));

    // Cycle 4: Another cycle with expired lifetime
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd5);
    step_clk();
    $display("Cycle 4 (Expired): PE[0][0] Product = %0d (Expected: 0)", get_pe_acc(0,0));

    if (get_pe_acc(0,0) !== 32'd0) begin
        $display("ERROR: Lifetime clamping failed! Product output non-zero after expiry: %0d", get_pe_acc(0,0));
        error_count++;
    end else begin
        $display("PASS: Lifetime counter properly clamped compute to zero upon expiration!");
    end

    // Reload lifetime and verify compute resumes
    lifetime_ld[0]     = 1'b1;
    lifetime_init[3:0] = 4'd5;
    step_clk();
    lifetime_ld[0]     = 1'b0;

    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd4); // 10 * 4 = 40
    step_clk();
    $display("Cycle 5 (Reloaded): PE[0][0] Product = %0d (Expected: 40)", get_pe_acc(0,0));

    if (get_pe_acc(0,0) !== 32'd40) begin
        $display("ERROR: Compute did not resume after lifetime reload: %0d", get_pe_acc(0,0));
        error_count++;
    end else begin
        $display("PASS: Compute resumed cleanly after lifetime renewal!");
    end
endtask
