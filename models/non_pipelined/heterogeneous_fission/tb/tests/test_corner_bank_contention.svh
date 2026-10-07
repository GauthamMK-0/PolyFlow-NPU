// test_corner_bank_contention.svh — TEST: Multi-Tenant Concurrent Bank Contention
// Verifies mutual exclusion and starvation avoidance under simultaneous requests for the same memory bank.

task automatic run_test_corner_bank_contention();
    $display("\n--- [TEST: CORNER] Multi-Tenant Concurrent Bank Contention ---");

    // Both Region A and Region B simultaneously request Bank 0
    token_req_A[0] = 1'b1;
    token_req_B[0] = 1'b1;
    step_clk();

    // Verify mutual exclusion: Exactly ONE region must be granted Bank 0, never both!
    $display("Simultaneous Request on Bank 0: grant_A=%0b, grant_B=%0b, owner=%0d",
             token_grant_bus[0], token_grant_bus[1], token_owner_bus[0]);

    if (token_grant_bus[0] && token_grant_bus[1]) begin
        $display("CRITICAL ERROR: Mutual exclusion VIOLATED on Bank 0! Both regions granted simultaneously!");
        error_count++;
    end else if (!token_grant_bus[0] && !token_grant_bus[1] && !token_held_bus[0]) begin
        $display("ERROR: Deadlock! Neither region was granted Bank 0 under concurrent request.");
        error_count++;
    end else begin
        $display("PASS: Mutual exclusion held under concurrent contention!");
    end

    // Identify who won (e.g. Region A with priority_base=0)
    if (token_grant_bus[0] || (token_held_bus[0] && token_owner_bus[0] == 1'b0)) begin
        $display("Region A acquired Bank 0. Region B pending...");
        // Region A releases Bank 0 while Region B keeps requesting
        token_release_A[0] = 1'b1;
        step_clk();
        token_release_A[0] = 1'b0;
        token_req_A[0]     = 1'b0;
        step_clk();

        // Now Region B must receive ownership
        $display("After Region A release: grant_A=%0b, grant_B=%0b, owner=%0d",
                 token_grant_bus[0], token_grant_bus[1], token_owner_bus[0]);
        if (token_grant_bus[1] || (token_held_bus[0] && token_owner_bus[0] == 1'b1)) begin
            $display("PASS: Region B successfully acquired Bank 0 after Region A release!");
        end else begin
            $display("ERROR: Region B starved or failed to acquire released bank!");
            error_count++;
        end

        // Clean up Region B
        token_release_B[0] = 1'b1;
        step_clk();
        token_release_B[0] = 1'b0;
        token_req_B[0]     = 1'b0;
        step_clk();
    end
endtask
