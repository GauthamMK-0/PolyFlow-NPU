// test_mem_scrub_migration.svh — TEST 4: Shared Memory Ownership Migration with Mandatory Scrubbing
// Included in hdf_top_tb.sv

task automatic run_test_mem_scrub_migration();
    $display("\n--- [TEST 4] Shared Memory Migration (Bank 0 -> Region B) ---");
    // Reassign Bank 0 to Region B with role Input-Issuer (2'b01)
    role_reassign[0]          = 1'b1;
    new_region_id_per_bank[0] = 1'b1;
    new_role_per_bank[0 +: 2] = 2'b01;
    step_clk();
    role_reassign[0]          = 1'b0;

    for (int i = 0; i < 3; i++) begin
        $display("Bank 0 Scrub Cycle %0d: scrub_active = %b", i+1, scrub_active_bus[0]);
        step_clk();
    end
    step_clk(); // 4th cycle completes scrub

    $display("Bank 0 Scrub Completed: bank_role_clear = %b", bank_role_clear_bus[0]);
    if (bank_role_clear_bus[0] !== 1'b1) begin
        $display("ERROR: Expected bank_role_clear pulse!");
        error_count++;
    end else begin
        $display("PASS: Memory bank migration and scrubbing safety verified.");
    end
endtask
