// test_random_stimulus.svh — TEST: Constrained-Random Stimulus with Self-Checking Golden Reference (Non-Pipelined)
// Exercises multi-cycle matrix operations with pseudorandom integer inputs and verifies arithmetic against golden model.

task automatic run_test_random_stimulus();
    localparam int NUM_RANDOM_CYCLES = 10;
    logic signed [ACC_W-1:0] expected_A [NUM_ROWS][2];
    logic signed [ACC_W-1:0] expected_B [NUM_ROWS][2];
    logic signed [DATA_W-1:0] rand_w_A [NUM_ROWS];
    logic signed [DATA_W-1:0] rand_x_A [NUM_ROWS];
    logic signed [DATA_W-1:0] rand_q_B [2];
    logic signed [DATA_W-1:0] rand_k_B [NUM_ROWS];
    int errors_in_test;

    $display("\n--- [TEST: RANDOM] Constrained-Random Stimulus with Self-Checking Model (%0d Cycles) ---", NUM_RANDOM_CYCLES);

    // Sweep remaining cross dataflow combinations to exercise all 9 pairs
    dataflow_mode = {2'b00, 2'b00}; step_clk(); // WS, WS
    dataflow_mode = {2'b10, 2'b00}; step_clk(); // WS, IS
    dataflow_mode = {2'b00, 2'b01}; step_clk(); // OS, WS
    dataflow_mode = {2'b01, 2'b01}; step_clk(); // OS, OS
    dataflow_mode = {2'b01, 2'b10}; step_clk(); // IS, OS
    dataflow_mode = {2'b10, 2'b10}; step_clk(); // IS, IS

    // Initialize accumulators & golden reference for random compute
    acc_clr = 2'b11;
    dataflow_mode = {2'b01, 2'b00}; // Reg B: OS, Reg A: WS
    cfg_split_col = 4'd2;
    cfg_update_strobe = 1'b1;
    lifetime_ld = 2'b11;
    lifetime_init = {4'd15, 4'd15};
    step_clk();
    cfg_update_strobe = 1'b0;
    lifetime_ld = 2'b00;
    acc_clr = 2'b00;

    // Step 1: Preload random stationary weights for Region A
    w_ld[0] = 1'b1;
    for (int r = 0; r < NUM_ROWS; r++) begin
        rand_w_A[r] = 8'($urandom_range(1, 10));
        set_din_w_a(r, rand_w_A[r]);
    end
    step_clk();
    w_ld[0] = 1'b0;

    errors_in_test = 0;

    // Step 2: Stream random activations for Region A and random Q/K for Region B over multiple cycles
    for (int cycle = 0; cycle < NUM_RANDOM_CYCLES; cycle++) begin
        // Region A streaming activations from West
        for (int r = 0; r < NUM_ROWS; r++) begin
            rand_x_A[r] = 8'($urandom_range(1, 8));
            set_din_w_a(r, rand_x_A[r]);
            for (int c = 0; c < 2; c++) begin
                expected_A[r][c] = rand_w_A[r] * rand_x_A[r];
            end
        end

        // Region B: Q from North (cols 2, 3), K from West (rows 0..3)
        for (int c = 0; c < 2; c++) begin
            rand_q_B[c] = 8'($urandom_range(1, 8));
            set_din_n(c + 2, rand_q_B[c]);
        end
        for (int r = 0; r < NUM_ROWS; r++) begin
            rand_k_B[r] = 8'($urandom_range(1, 8));
            set_din_w_b(r, rand_k_B[r]);
            for (int c = 0; c < 2; c++) begin
                expected_B[r][c] = rand_q_B[c] * rand_k_B[r];
            end
        end

        step_clk();

        // Verify cycle output against golden combinational reference
        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < 2; c++) begin
                logic signed [ACC_W-1:0] dut_val_A;
                dut_val_A = get_pe_acc(r, c);
                if (dut_val_A !== expected_A[r][c]) begin
                    $display("ERROR: Cycle %0d Region A PE[%0d][%0d] Mismatch! DUT=%0d, Golden=%0d",
                             cycle, r, c, dut_val_A, expected_A[r][c]);
                    errors_in_test++;
                end
            end
        end

        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < 2; c++) begin
                logic signed [ACC_W-1:0] dut_val_B;
                dut_val_B = get_pe_acc(r, c + 2);
                if (dut_val_B !== expected_B[r][c]) begin
                    $display("ERROR: Cycle %0d Region B PE[%0d][%0d] Mismatch! DUT=%0d, Golden=%0d",
                             cycle, r, c + 2, dut_val_B, expected_B[r][c]);
                    errors_in_test++;
                end
            end
        end
    end

    if (errors_in_test == 0) begin
        $display("PASS: All 16 PEs verified accurately against Golden Mathematical Model across %0d random cycles!", NUM_RANDOM_CYCLES);
    end else begin
        $display("ERROR: Random stimulus test found %0d arithmetic mismatches!", errors_in_test);
        error_count += errors_in_test;
    end
endtask
