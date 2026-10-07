// test_corner_compute_gating.svh — TEST: Compute Enable Gating & Clamping (Pipelined)
// Verifies independent per-region compute enabling and freeze behavior.

task automatic run_test_corner_compute_gating();
    $display("\n--- [TEST: CORNER] Per-Region Compute Enable Gating & Freezing ---");
    acc_clr = 2'b11;
    compute_en = 2'b00;
    step_clk();
    acc_clr = 2'b00;

    // Preload stationary weights: Reg A = 5, Reg B = 7
    w_ld = 2'b11;
    for (int r = 0; r < NUM_ROWS; r++) begin
        set_din_w_a(r, 8'd5);
        set_din_w_b(r, 8'd7);
    end
    step_clk();
    w_ld = 2'b00;

    // Cycle 1: Both enabled (2'b11) -> Reg A accumulates 15, Reg B accumulates 14
    compute_en = 2'b11;
    for (int r = 0; r < NUM_ROWS; r++) begin
        set_din_w_a(r, 8'd3);
        set_din_w_b(r, 8'd2);
    end
    step_clk();
    $display("Cycle 1 (Both Active): Reg A PE[0][0]=%0d, Reg B PE[0][2]=%0d", get_pe_acc(0,0), get_pe_acc(0,2));
    if (get_pe_acc(0,0) !== 32'd15 || get_pe_acc(0,2) !== 32'd14) begin
        $display("ERROR: Cycle 1 active compute mismatch!");
        error_count++;
    end

    // Cycle 2: Both disabled (2'b00) -> accumulators MUST freeze at 15 and 14
    compute_en = 2'b00;
    for (int r = 0; r < NUM_ROWS; r++) begin
        set_din_w_a(r, 8'd3);
        set_din_w_b(r, 8'd2);
    end
    step_clk();
    $display("Cycle 2 (Gated): Reg A PE[0][0]=%0d (Exp: 15), Reg B PE[0][2]=%0d (Exp: 14)", get_pe_acc(0,0), get_pe_acc(0,2));
    if (get_pe_acc(0,0) !== 32'd15 || get_pe_acc(0,2) !== 32'd14) begin
        $display("ERROR: Compute gating failed! Accumulator updated while compute_en=0");
        error_count++;
    end else begin
        $display("PASS: Accumulators successfully frozen when compute_en=0.");
    end

    // Cycle 3: Region A enabled only (2'b01) -> Reg A = 15+15=30, Reg B frozen at 14
    compute_en = 2'b01;
    for (int r = 0; r < NUM_ROWS; r++) begin
        set_din_w_a(r, 8'd3);
        set_din_w_b(r, 8'd2);
    end
    step_clk();
    $display("Cycle 3 (Reg A Only): Reg A PE[0][0]=%0d (Exp: 30), Reg B PE[0][2]=%0d (Exp: 14)", get_pe_acc(0,0), get_pe_acc(0,2));
    if (get_pe_acc(0,0) !== 32'd30 || get_pe_acc(0,2) !== 32'd14) begin
        $display("ERROR: Region A only compute mismatch!");
        error_count++;
    end

    // Cycle 4: Region B enabled only (2'b10) -> Reg A frozen at 30, Reg B = 14+14=28
    compute_en = 2'b10;
    for (int r = 0; r < NUM_ROWS; r++) begin
        set_din_w_a(r, 8'd3);
        set_din_w_b(r, 8'd2);
    end
    step_clk();
    $display("Cycle 4 (Reg B Only): Reg A PE[0][0]=%0d (Exp: 30), Reg B PE[0][2]=%0d (Exp: 28)", get_pe_acc(0,0), get_pe_acc(0,2));
    if (get_pe_acc(0,0) !== 32'd30 || get_pe_acc(0,2) !== 32'd28) begin
        $display("ERROR: Region B only compute mismatch!");
        error_count++;
    end else begin
        $display("PASS: Independent per-region compute gating verified cleanly.");
    end

    compute_en = 2'b00;
endtask
