// test_random_stimulus.svh — TEST: Constrained-Random Stimulus with Self-Checking Golden Reference (Spatial Fission Pipelined)
// Exercises multi-cycle dual-tenant WS operations with pseudorandom integer inputs and verifies arithmetic against golden model.

task automatic run_test_random_stimulus();
    localparam int NUM_RANDOM_CYCLES = 10;
    logic signed [ACC_W-1:0] golden_acc_A [NUM_ROWS][2];
    logic signed [ACC_W-1:0] golden_acc_B [NUM_ROWS][2];
    logic signed [DATA_W-1:0] rand_w_A [NUM_ROWS];
    logic signed [DATA_W-1:0] rand_w_B [NUM_ROWS];
    logic signed [DATA_W-1:0] rand_x_A [NUM_ROWS];
    logic signed [DATA_W-1:0] rand_x_B [NUM_ROWS];
    int errors_in_test;

    $display("\n--- [TEST: RANDOM] Constrained-Random Stimulus with Self-Checking Model (%0d Cycles) ---", NUM_RANDOM_CYCLES);

    // Initialize accumulators & golden reference for random compute
    acc_clr = 2'b11;
    compute_en = 2'b00;
    cfg_split_col = 4'd2;
    cfg_update_strobe = 1'b1;
    step_clk();
    cfg_update_strobe = 1'b0;
    acc_clr = 2'b00;

    for (int r = 0; r < NUM_ROWS; r++) begin
        for (int c = 0; c < 2; c++) begin
            golden_acc_A[r][c] = '0;
            golden_acc_B[r][c] = '0;
        end
    end

    // Step 1: Preload random stationary weights for both regions
    w_ld = 2'b11;
    for (int r = 0; r < NUM_ROWS; r++) begin
        rand_w_A[r] = 8'($urandom_range(1, 10));
        rand_w_B[r] = 8'($urandom_range(1, 10));
        set_din_w_a(r, rand_w_A[r]);
        set_din_w_b(r, rand_w_B[r]);
    end
    step_clk();
    w_ld = 2'b00;

    // Step 2: Stream random activations for both regions over multiple cycles
    compute_en = 2'b11;
    for (int cycle = 0; cycle < NUM_RANDOM_CYCLES; cycle++) begin
        for (int r = 0; r < NUM_ROWS; r++) begin
            rand_x_A[r] = 8'($urandom_range(1, 8));
            rand_x_B[r] = 8'($urandom_range(1, 8));
            set_din_w_a(r, rand_x_A[r]);
            set_din_w_b(r, rand_x_B[r]);

            for (int c = 0; c < 2; c++) begin
                golden_acc_A[r][c] += rand_w_A[r] * rand_x_A[r];
                golden_acc_B[r][c] += rand_w_B[r] * rand_x_B[r];
            end
        end
        step_clk();
    end
    compute_en = 2'b00;

    // Step 3: Self-checking verification across all PEs in both regions
    errors_in_test = 0;
    for (int r = 0; r < NUM_ROWS; r++) begin
        for (int c = 0; c < 2; c++) begin
            logic signed [ACC_W-1:0] dut_val_A;
            dut_val_A = get_pe_acc(r, c);
            if (dut_val_A !== golden_acc_A[r][c]) begin
                $display("ERROR: Region A PE[%0d][%0d] Mismatch! DUT=%0d, Golden=%0d",
                         r, c, dut_val_A, golden_acc_A[r][c]);
                errors_in_test++;
            end
        end
    end

    for (int r = 0; r < NUM_ROWS; r++) begin
        for (int c = 0; c < 2; c++) begin
            logic signed [ACC_W-1:0] dut_val_B;
            dut_val_B = get_pe_acc(r, c + 2);
            if (dut_val_B !== golden_acc_B[r][c]) begin
                $display("ERROR: Region B PE[%0d][%0d] Mismatch! DUT=%0d, Golden=%0d",
                         r, c + 2, dut_val_B, golden_acc_B[r][c]);
                errors_in_test++;
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
