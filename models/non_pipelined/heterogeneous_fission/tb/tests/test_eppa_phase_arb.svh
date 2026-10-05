// test_eppa_phase_arb.svh — TEST 3: Dynamic EPPA Phase Arbitration under Heterogeneous Loads
// Included in hdf_top_tb.sv

task automatic run_test_eppa_phase_arb();
    $display("\n--- [TEST 3] EPPA Bandwidth Arbitration (WS BURST + OS STREAM) ---");
    // Region A is in BURST (00), Region B is in STREAM (10)
    phase_tag = {2'b10, 2'b00};
    step_clk();

    $display("BW Alloc: Region A (BURST) = 0x%0h (Exp: 0xFF), Region B (STREAM) = 0x%0h (Exp: 0x7F)",
             bw_alloc[0 +: BW_W], bw_alloc[BW_W +: BW_W]);

    if (bw_alloc[0 +: BW_W] !== 8'hFF || bw_alloc[BW_W +: BW_W] !== 8'h7F) begin
        $display("ERROR: EPPA bandwidth allocation mismatch!");
        error_count++;
    end else begin
        $display("PASS: EPPA dynamic allocation correctly reflects heterogeneous memory phase profiles.");
    end
endtask
