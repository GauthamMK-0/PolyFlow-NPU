// test_eppa_phase_arb.svh — TEST 3: Dynamic EPPA Phase Arbitration under Heterogeneous Loads
// Included in hdf_top_tb.sv

task automatic run_test_eppa_phase_arb();
    $display("\n--- [TEST 3] EPPA Bandwidth Arbitration (WS BURST + OS STREAM) ---");
    // Phase Test 1: Region A in BURST (00), Region B in STREAM (10)
    phase_tag = {2'b10, 2'b00};
    step_clk();

    $display("BW Alloc (BURST + STREAM): Region A = 0x%0h (Exp: 0xFF), Region B = 0x%0h (Exp: 0x7F)",
             bw_alloc[0 +: BW_W], bw_alloc[BW_W +: BW_W]);

    if (bw_alloc[0 +: BW_W] !== 8'hFF || bw_alloc[BW_W +: BW_W] !== 8'h7F) begin
        $display("ERROR: EPPA bandwidth allocation mismatch!");
        error_count++;
    end else begin
        $display("PASS: EPPA dynamic allocation correctly reflects heterogeneous memory phase profiles.");
    end

    // Phase Test 2: Inverted phases (Region A in STREAM (10), Region B in BURST (00))
    phase_tag = {2'b00, 2'b10};
    step_clk();
    $display("BW Alloc (STREAM + BURST): Region A = 0x%0h (Exp: 0x7F), Region B = 0x%0h (Exp: 0xFF)",
             bw_alloc[0 +: BW_W], bw_alloc[BW_W +: BW_W]);
    if (bw_alloc[0 +: BW_W] !== 8'h7F || bw_alloc[BW_W +: BW_W] !== 8'hFF) begin
        $display("ERROR: EPPA inverted bandwidth allocation mismatch!");
        error_count++;
    end

    // Phase Test 3: Both IDLE (01)
    phase_tag = {2'b01, 2'b01};
    step_clk();

    // Phase Test 4: RECONFIG phase (11) triggering reconfig_urgent
    phase_tag = {2'b11, 2'b11};
    step_clk();
    $display("RECONFIG Phase: reconfig_urgent = %02b (Exp: 11)", reconfig_urgent);
    if (reconfig_urgent !== 2'b11) begin
        $display("ERROR: reconfig_urgent signal failed to assert during RECONFIG phase!");
        error_count++;
    end else begin
        $display("PASS: EPPA RECONFIG urgency flags verified across all tenant regions.");
    end

    // Restore IDLE
    phase_tag = {2'b01, 2'b01};
    step_clk();
endtask
