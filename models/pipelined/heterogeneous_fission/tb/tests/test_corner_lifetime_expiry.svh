// test_corner_lifetime_expiry.svh — TEST: Tenant Lifetime Expiration & Auto-Clamping
// Verifies that when a tenant's hardware lifetime expires, PE compute clamps to zero to prevent unbudgeted execution.

task automatic run_test_corner_lifetime_expiry();
    $display("\n--- [TEST: CORNER] Tenant Lifetime Expiration & Auto-Clamping ---");
    acc_clr = 2'b11;
    dataflow_mode = {2'b00, 2'b00}; // Both regions WS mode
    step_clk();
    acc_clr = 2'b00;

    // Preload stationary weight for Region A
    w_ld[0] = 1'b1;
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd10);
    step_clk();
    w_ld[0] = 1'b0;

    // Load lifetime_cnt = 2 for Region A
    lifetime_ld[0]     = 1'b1;
    lifetime_init[3:0] = 4'd2; // 2 cycles lifetime
    step_clk();
    lifetime_ld[0]     = 1'b0;

    // Cycle 1: Stream activation 3 -> PE accumulates 10 * 3 = 30
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
    step_clk();
    $display("Cycle 1 (Active): PE[0][0] Acc = %0d", get_pe_acc(0,0));

    // Cycle 2: Stream activation 3 -> PE accumulates 10 * 3 = 30 (total = 60)
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
    step_clk();
    $display("Cycle 2 (Active): PE[0][0] Acc = %0d", get_pe_acc(0,0));

    // Cycle 3: Lifetime has expired (cnt == 0). Stream activation 3.
    // The accumulator should NOT change because mac_en is deasserted.
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
    step_clk();
    $display("Cycle 3 (Expired): PE[0][0] Acc = %0d (Expected: 60)", get_pe_acc(0,0));

    // Cycle 4: Another cycle with expired lifetime
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd5);
    step_clk();
    $display("Cycle 4 (Expired): PE[0][0] Acc = %0d (Expected: 60)", get_pe_acc(0,0));

    if (get_pe_acc(0,0) !== 32'd60) begin
        $display("ERROR: Lifetime clamping failed! Accumulator continued running after expiry: %0d", get_pe_acc(0,0));
        error_count++;
    end else begin
        $display("PASS: Lifetime counter properly clamped compute upon expiration!");
    end

    // Reload lifetime and verify compute resumes
    lifetime_ld[0]     = 1'b1;
    lifetime_init[3:0] = 4'd5;
    step_clk();
    lifetime_ld[0]     = 1'b0;

    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd4); // 10 * 4 = 40 -> acc = 60 + 40 = 100
    step_clk();
    $display("Cycle 5 (Reloaded): PE[0][0] Acc = %0d (Expected: 100)", get_pe_acc(0,0));

    if (get_pe_acc(0,0) !== 32'd100) begin
        $display("ERROR: Compute did not resume after lifetime reload: %0d", get_pe_acc(0,0));
        error_count++;
    end else begin
        $display("PASS: Compute resumed cleanly after lifetime renewal!");
    end
endtask
