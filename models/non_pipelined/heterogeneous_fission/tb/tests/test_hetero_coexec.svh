// test_hetero_coexec.svh — TEST 2: Heterogeneous Co-Execution: Region A (WS) + Region B (OS)
// Included in hdf_top_tb.sv (Non-Pipelined Combinational)

task automatic run_test_hetero_coexec();
    $display("\n--- [TEST 2] Heterogeneous Co-Execution: Region A (WS) + Region B (OS) ---");
    // Clear accumulators in both regions
    acc_clr = 2'b11;
    dataflow_mode = {2'b01, 2'b00}; // Reg B: OS (01), Reg A: WS (00)
    step_clk();
    acc_clr = 2'b00;

    // Step 2.1: Preload weights for Region A (WS) & initialize lifetime counter for both
    w_ld[0]          = 1'b1;
    lifetime_ld      = 2'b11;
    lifetime_init    = {4'd15, 4'd15}; // 15 cycles lifetime for both regions
    for (int r = 0; r < NUM_ROWS; r++) begin
        set_din_w_a(r, 8'd5); // Region A stationary weight = 5
    end
    step_clk();
    w_ld[0]     = 1'b0;
    lifetime_ld = 2'b00;

    // Step 2.2: Concurrent execution:
    // Region A receives streaming activations from West: x_A = 3
    // Region B receives Q from North and K from West simultaneously:
    // Cycle 1: Q=4, K=7 -> Region B prod = 28; Region A prod = 5*3 = 15
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
    for (int c = 2; c < NUM_COLS; c++) set_din_n(c, 8'd4);  // Q into Region B cols 2-3
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_b(r, 8'd7); // K into Region B rows
    step_clk();

    $display("Cycle 1: Region A (WS Mode) Product = %0d (Expected: 15)", get_pe_acc(0,0));
    $display("Cycle 1: Region B (OS Mode) Product = %0d (Expected: 28)", get_pe_acc(0,2));

    if (get_pe_acc(0,0) !== 32'd15 || get_pe_acc(0,2) !== 32'd28) begin
        $display("ERROR: Cycle 1 combinational mismatch!");
        error_count++;
    end

    // Cycle 2: Q=2, K=6 -> Region B prod = 12; Region A prod = 15
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
    for (int c = 2; c < NUM_COLS; c++) set_din_n(c, 8'd2);
    for (int r = 0; r < NUM_ROWS; r++) set_din_w_b(r, 8'd6);
    step_clk();

    $display("Cycle 2: Region A (WS Mode) Product = %0d (Expected: 15)", get_pe_acc(0,0));
    $display("Cycle 2: Region B (OS Mode) Product = %0d (Expected: 12)", get_pe_acc(0,2));

    if (get_pe_acc(0,0) !== 32'd15 || get_pe_acc(0,2) !== 32'd12) begin
        $display("ERROR: Heterogeneous co-execution calculation mismatch!");
        error_count++;
    end else begin
        $display("PASS: Region A (WS) and Region B (OS) executed simultaneously with correct combinational mathematics!");
    end
endtask
