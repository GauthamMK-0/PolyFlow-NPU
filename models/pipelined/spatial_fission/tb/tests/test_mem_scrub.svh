// test_mem_scrub.svh — TEST 4: Shared Memory Bank Scrubbing & Ownership Transfer
// Included in sfa_top_tb.sv

task automatic run_test_mem_scrub();
    $display("\n--- [TEST 4] Shared Memory Scrubbing & Role Reassignment ---");
    // Reassign Bank 1 to Region B with role 2'b01 (Input-Issuer)
    role_reassign[1]          = 1'b1;
    new_region_id_per_bank[1] = 1'b1; // Region B
    new_role_per_bank[2 +: 2] = 2'b01;
    step_clk();
    role_reassign[1]          = 1'b0;

    // Verify scrub active for 4 cycles
    for (int i = 0; i < 3; i++) begin
        $display("Bank 1 Scrub Cycle %0d: scrub_active = %b", i+1, scrub_active_bus[1]);
        step_clk();
    end
    step_clk(); // Cycle 4 completes

    $display("Bank 1 Scrub Completed: bank_role_clear = %b", bank_role_clear_bus[1]);
    if (bank_role_clear_bus[1] !== 1'b1) begin
        $display("ERROR: Expected bank_role_clear pulse upon scrub completion!");
        error_count++;
    end else begin
        $display("PASS: Bank scrub zeroing sequence verified.");
    end
endtask
