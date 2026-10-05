// test_concurrent_ws.svh — TEST 2: Concurrent Multi-Tenant WS Execution & Boundary Isolation
// Included in sfa_top_tb.sv (Non-Pipelined Combinational)

task automatic run_test_concurrent_ws();
    $display("\n--- [TEST 2] Concurrent Execution: Region A & Region B (Both WS) ---");
    // Clear accumulators in both regions
    acc_clr = 2'b11;
    step_clk();
    acc_clr = 2'b00;

    // Step 2.1: Preload weights into Region A (w=5) and Region B (w=7)
    w_ld = 2'b11;
    for (int r = 0; r < NUM_ROWS; r++) begin
        set_din_w_a(r, 8'd5); // Region A weight = 5
        set_din_w_b(r, 8'd7); // Region B weight = 7
    end
    step_clk();
    w_ld = 2'b00;

    // Step 2.2: Stream distinct activations: Region A (x=3), Region B (x=2)
    compute_en = 2'b11;
    for (int r = 0; r < NUM_ROWS; r++) begin
        set_din_w_a(r, 8'd3); // Region A activation = 3
        set_din_w_b(r, 8'd2); // Region B activation = 2
    end
    step_clk(); // Combinational product: Reg A = 5*3=15, Reg B = 7*2=14

    $display("Region A (PE[0][0]) Product = %0d (Expected: 15)", get_pe_acc(0,0));
    $display("Region B (PE[0][2]) Product = %0d (Expected: 14)", get_pe_acc(0,2));

    if (get_pe_acc(0,0) !== 32'd15 || get_pe_acc(0,2) !== 32'd14) begin
        $display("ERROR: Concurrent execution calculation mismatch!");
        error_count++;
    end else begin
        $display("PASS: Both regions co-executed successfully with zero cross-talk (combinational).");
    end
    compute_en = 2'b00;
endtask
