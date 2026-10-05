// test_eppa_phase_arb.svh — TEST 3: EPPA Memory Bandwidth Arbitration
// Included in sfa_top_tb.sv

task automatic run_test_eppa_phase_arb();
    $display("\n--- [TEST 3] EPPA Memory Bandwidth Arbitration ---");
    // Region A -> BURST (00), Region B -> STREAM (10)
    phase_tag = {2'b10, 2'b00}; // [1]=Region B (STREAM), [0]=Region A (BURST)
    step_clk();

    $display("BW Alloc: Region A = 0x%0h (Exp: 0xFF), Region B = 0x%0h (Exp: 0x7F)",
             bw_alloc[0 +: BW_W], bw_alloc[BW_W +: BW_W]);

    if (bw_alloc[0 +: BW_W] !== 8'hFF || bw_alloc[BW_W +: BW_W] !== 8'h7F) begin
        $display("ERROR: EPPA bandwidth allocation mismatch!");
        error_count++;
    end else begin
        $display("PASS: EPPA dynamic allocation verified.");
    end
endtask
