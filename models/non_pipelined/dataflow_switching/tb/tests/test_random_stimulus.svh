// test_random_stimulus.svh — TEST: Constrained-Random Stimulus with Self-Checking Golden Reference (DFS Non-Pipelined)
// Exercises multi-cycle matrix operations across WS, OS, and IS dataflow modes with pseudorandom integer inputs.

task automatic run_test_random_stimulus();
    localparam int NUM_RANDOM_CYCLES = 8;
    logic signed [ACC_W-1:0] expected_val [NUM_ROWS][NUM_COLS];
    logic signed [DATA_W-1:0] rand_w [NUM_ROWS];
    logic signed [DATA_W-1:0] rand_x [NUM_ROWS];
    logic signed [DATA_W-1:0] rand_q [NUM_COLS];
    logic signed [DATA_W-1:0] rand_k [NUM_ROWS];
    int errors_in_test;

    $display("\n--- [TEST: RANDOM] Constrained-Random Multi-Mode Stimulus (DFS Non-Pipelined) ---");
    errors_in_test = 0;

    // ==============================================================
    // Mode 1: Weight-Stationary (WS) Random Combinational Execution
    // ==============================================================
    $display(">>> Mode 1: Random WS Combinational Sweep (%0d Cycles) <<<", NUM_RANDOM_CYCLES);
    cfg_dataflow_mode = 2'b00;
    tile_acc_clr      = 1;
    tile_compute_en   = 0;
    step_clk();
    tile_acc_clr      = 0;

    // Preload random stationary weights
    tile_w_ld = 1;
    for (int r = 0; r < NUM_ROWS; r++) begin
        rand_w[r] = 8'($urandom_range(1, 10));
        set_din_w(r, rand_w[r]);
    end
    step_clk();
    tile_w_ld = 0;

    // Stream random activations
    tile_compute_en = 1;
    for (int cycle = 0; cycle < NUM_RANDOM_CYCLES; cycle++) begin
        for (int r = 0; r < NUM_ROWS; r++) begin
            rand_x[r] = 8'($urandom_range(1, 8));
            set_din_w(r, rand_x[r]);
            for (int c = 0; c < NUM_COLS; c++) begin
                expected_val[r][c] = rand_w[r] * rand_x[r];
            end
        end
        step_clk();

        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < NUM_COLS; c++) begin
                if (get_pe_acc(r, c) !== expected_val[r][c]) begin
                    $display("ERROR: Cycle %0d WS PE[%0d][%0d] Mismatch! DUT=%0d, Exp=%0d",
                             cycle, r, c, get_pe_acc(r, c), expected_val[r][c]);
                    errors_in_test++;
                end
            end
        end
    end
    tile_compute_en = 0;

    // ==============================================================
    // Mode 2: Output-Stationary (OS) Random Combinational Execution
    // ==============================================================
    $display(">>> Mode 2: Random OS Combinational Sweep (%0d Cycles) <<<", NUM_RANDOM_CYCLES);
    cfg_dataflow_mode = 2'b01;
    tile_acc_clr      = 1;
    tile_compute_en   = 0;
    step_clk();
    tile_acc_clr      = 0;

    tile_compute_en = 1;
    for (int cycle = 0; cycle < NUM_RANDOM_CYCLES; cycle++) begin
        for (int c = 0; c < NUM_COLS; c++) begin
            rand_q[c] = 8'($urandom_range(1, 8));
            set_din_n(c, rand_q[c]);
        end
        for (int r = 0; r < NUM_ROWS; r++) begin
            rand_k[r] = 8'($urandom_range(1, 8));
            set_din_w(r, rand_k[r]);
            for (int c = 0; c < NUM_COLS; c++) begin
                expected_val[r][c] = rand_q[c] * rand_k[r];
            end
        end
        step_clk();

        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < NUM_COLS; c++) begin
                if (get_pe_acc(r, c) !== expected_val[r][c]) begin
                    $display("ERROR: Cycle %0d OS PE[%0d][%0d] Mismatch! DUT=%0d, Exp=%0d",
                             cycle, r, c, get_pe_acc(r, c), expected_val[r][c]);
                    errors_in_test++;
                end
            end
        end
    end
    tile_compute_en = 0;

    // ==============================================================
    // Mode 3: Input-Stationary (IS) Random Combinational Execution
    // ==============================================================
    $display(">>> Mode 3: Random IS Combinational Sweep (%0d Cycles) <<<", NUM_RANDOM_CYCLES);
    cfg_dataflow_mode = 2'b10;
    tile_acc_clr      = 1;
    tile_compute_en   = 0;
    step_clk();
    tile_acc_clr      = 0;

    // Preload random stationary activations from North
    tile_w_ld = 1;
    for (int c = 0; c < NUM_COLS; c++) begin
        rand_q[c] = 8'($urandom_range(1, 10));
        set_din_n(c, rand_q[c]);
    end
    step_clk();
    tile_w_ld = 0;

    // Stream random weights from West
    tile_compute_en = 1;
    for (int cycle = 0; cycle < NUM_RANDOM_CYCLES; cycle++) begin
        for (int r = 0; r < NUM_ROWS; r++) begin
            rand_k[r] = 8'($urandom_range(1, 8));
            set_din_w(r, rand_k[r]);
            for (int c = 0; c < NUM_COLS; c++) begin
                expected_val[r][c] = rand_q[c] * rand_k[r];
            end
        end
        step_clk();

        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < NUM_COLS; c++) begin
                if (get_pe_acc(r, c) !== expected_val[r][c]) begin
                    $display("ERROR: Cycle %0d IS PE[%0d][%0d] Mismatch! DUT=%0d, Exp=%0d",
                             cycle, r, c, get_pe_acc(r, c), expected_val[r][c]);
                    errors_in_test++;
                end
            end
        end
    end
    tile_compute_en = 0;

    if (errors_in_test == 0) begin
        $display("PASS: All 16 PEs verified accurately against Golden Mathematical Model across all 3 dataflows!");
    end else begin
        $display("ERROR: Random stimulus test encountered %0d arithmetic mismatches!", errors_in_test);
        error_count += errors_in_test;
    end
endtask
