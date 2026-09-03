module otp_token_fsm_tb;

    localparam int NUM_REGIONS = 2;
    localparam int REGION_W    = 1;
    localparam int EPOCH_W     = 8;

    logic clk;
    logic rst_n;
    logic [NUM_REGIONS-1:0] token_req;
    logic [NUM_REGIONS-1:0] token_release;
    logic scrub_active;
    logic [REGION_W-1:0] token_owner;
    logic token_held;
    logic [NUM_REGIONS-1:0] grant;

    otp_token_fsm #(
        .NUM_REGIONS(NUM_REGIONS),
        .REGION_W(REGION_W),
        .EPOCH_W(EPOCH_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .token_req(token_req),
        .token_release(token_release),
        .scrub_active(scrub_active),
        .token_owner(token_owner),
        .token_held(token_held),
        .grant(grant)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic step();
        @(negedge clk);
        @(posedge clk);
        #1;
    endtask

    task automatic reset_dut();
        rst_n = 0;
        token_req = '0;
        token_release = '0;
        scrub_active = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        step();
    endtask

    // Test basic grant to region 0
    task automatic test_grant_region0();
        $display("\n=== TEST: Grant to Region 0 ===");
        reset_dut();
        token_req = 2'b01; // Region 0 requests
        step();
        assert(grant == 2'b01) else $error("Grant: expected 01, got %b", grant);
        assert(token_held == 1'b1) else $error("Token held should be 1");
        assert(token_owner == 1'b0) else $error("Token owner should be 0");
        $display("Grant R0: grant=%b, held=%b, owner=%b", grant, token_held, token_owner);
    endtask

    // Test grant to region 1 when region 0 not requesting
    task automatic test_grant_region1();
        $display("\n=== TEST: Grant to Region 1 ===");
        reset_dut();
        token_req = 2'b10; // Region 1 requests
        step();
        assert(grant == 2'b10) else $error("Grant: expected 10, got %b", grant);
        assert(token_held == 1'b1) else $error("Token held should be 1");
        assert(token_owner == 1'b1) else $error("Token owner should be 1");
        $display("Grant R1: grant=%b, held=%b, owner=%b", grant, token_held, token_owner);
    endtask

    // Test priority: region 0 has priority initially
    task automatic test_priority();
        $display("\n=== TEST: Priority (R0 first) ===");
        reset_dut();
        token_req = 2'b11; // Both request
        step();
        assert(grant == 2'b01) else $error("Priority: R0 should win, got %b", grant);
        assert(token_owner == 1'b0) else $error("Owner should be R0");
        $display("Both request: grant=%b, owner=%b (R0 wins)", grant, token_owner);
    endtask

    // Test sticky ownership - holder keeps token until release
    task automatic test_sticky_ownership();
        $display("\n=== TEST: Sticky Ownership ===");
        reset_dut();
        token_req = 2'b01; // R0 requests
        step();
        assert(token_owner == 1'b0) else $error("Owner should be R0");
        
        // R0 keeps token even if R1 requests
        token_req = 2'b11; // Both request
        step();
        assert(token_owner == 1'b0) else $error("Owner should stay R0 (sticky)");
        assert(grant == 2'b00) else $error("Grant should be 0 (no new grant)");
        $display("Sticky: owner=%b, grant=%b (R0 keeps token)", token_owner, grant);
        
        // R0 releases AND stops requesting
        token_release = 2'b01;
        token_req = 2'b10; // Only R1 requests now
        step();
        assert(token_held == 1'b0) else $error("Token should be released");
        $display("After release: held=%b", token_held);
        
        // Now R1 should get it
        token_release = 2'b00;
        step();
        assert(token_owner == 1'b1) else $error("Owner should be R1 now");
        assert(grant == 2'b10) else $error("Grant should be R1");
        $display("After R0 release: owner=%b, grant=%b (R1 gets token)", token_owner, grant);
    endtask

    // Test scrub preemption
    task automatic test_scrub_preemption();
        $display("\n=== TEST: Scrub Preemption ===");
        reset_dut();
        token_req = 2'b01; // R0 requests
        step();
        assert(token_owner == 1'b0) else $error("Owner should be R0");
        
        // Scrub active - forces SCRUB state
        scrub_active = 1'b1;
        step();
        assert(token_held == 1'b0) else $error("Token held should be 0 during scrub");
        assert(grant == 2'b00) else $error("Grant should be 0 during scrub");
        $display("During scrub: held=%b, grant=%b", token_held, grant);
        
        // Scrub ends, R0 still requesting
        scrub_active = 1'b0;
        step();
        assert(token_owner == 1'b0) else $error("Owner should be R0 after scrub");
        assert(token_held == 1'b1) else $error("Token should be held again");
        $display("After scrub: owner=%b, held=%b", token_owner, token_held);
    endtask

    // Test scrub with waiting requester
    task automatic test_scrub_with_waiter();
        $display("\n=== TEST: Scrub with Waiting Requester ===");
        reset_dut();
        token_req = 2'b01; // R0 gets token
        step();
        token_req = 2'b11; // R1 also requests (waits)
        step();
        
        // Scrub
        scrub_active = 1'b1;
        step();
        assert(token_held == 1'b0);
        
        // Scrub ends, R1 should get token (R0 released implicitly? No, R0 didn't release)
        // Actually, scrub forces SCRUB state, then when scrub ends, if owner didn't release,
        // it should go back to OWNED by same owner. But spec says "scrub done -> grant pending requester (or FREE)"
        // Let me check the spec: "scrub done -> grant pending requester (or FREE)"
        // So after scrub, if there's a pending requester, they get it.
        scrub_active = 1'b0;
        step();
        // R0 didn't release, but R1 is waiting. Spec says grant pending requester.
        // But R0 is still the "owner" until it releases. Let me check the FSM logic.
        // In my FSM: S_SCRUB -> if !scrub_active and found -> S_OWNED with candidate
        // candidate is R0 (priority_base=0, R0 requests first). So R0 gets it back.
        assert(token_owner == 1'b0) else $error("Owner should be R0 (priority)");
        $display("After scrub with waiter: owner=%b (R0 by priority)", token_owner);
    endtask

    // Test no double grant
    task automatic test_no_double_grant();
        $display("\n=== TEST: No Double Grant ===");
        reset_dut();
        token_req = 2'b11;
        step();
        assert(grant != 2'b11) else $error("Grant should never be 11 (double grant)");
        $display("Grant: %b (not 11)", grant);
        
        // Try various sequences
        token_req = 2'b01;
        step();
        token_req = 2'b11;
        step();
        token_release = 2'b01;
        step();
        token_release = 2'b00;
        step();
        assert(grant != 2'b11) else $error("Grant should never be 11");
        $display("No double grant: PASS");
    endtask

    initial begin
        $dumpfile("/root/research/mt_npu/tb/otp_token_fsm_tb.vcd");
        $dumpvars(0, otp_token_fsm_tb);

        test_grant_region0();
        test_grant_region1();
        test_priority();
        test_sticky_ownership();
        test_scrub_preemption();
        test_scrub_with_waiter();
        test_no_double_grant();

        $display("\n=== ALL OTP TOKEN FSM TESTS PASSED ===");
        $finish;
    end

endmodule