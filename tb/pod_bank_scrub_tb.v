module pod_bank_scrub_tb;

    localparam int REGION_W  = 1;
    localparam int SCRUB_CYC = 4;

    logic clk;
    logic rst_n;
    logic role_reassign;
    logic [REGION_W-1:0] new_region_id;
    logic [1:0] new_role;
    logic scrub_active;
    logic bank_role_clear;
    logic [REGION_W-1:0] region_owner;
    logic [1:0] role_tag;

    pod_bank_scrub #(
        .REGION_W(REGION_W),
        .SCRUB_CYC(SCRUB_CYC)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .role_reassign(role_reassign),
        .new_region_id(new_region_id),
        .new_role(new_role),
        .scrub_active(scrub_active),
        .bank_role_clear(bank_role_clear),
        .region_owner(region_owner),
        .role_tag(role_tag)
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
        role_reassign = 1'b0;
        new_region_id = '0;
        new_role = 2'b00;
        repeat (2) @(posedge clk);
        rst_n = 1;
        step();
    endtask

    // Test basic scrub cycle
    task automatic test_basic_scrub();
        $display("\n=== TEST: Basic Scrub Cycle ===");
        reset_dut();
        assert(scrub_active == 1'b0) else $error("Initial scrub_active should be 0");
        assert(bank_role_clear == 1'b0) else $error("Initial bank_role_clear should be 0");
        
        // Start scrub
        role_reassign = 1'b1;
        new_region_id = 1'b1;
        new_role = 2'b01; // Input-Issuer
        step();
        role_reassign = 1'b0;
        
        assert(scrub_active == 1'b1) else $error("scrub_active should be 1 after role_reassign");
        assert(bank_role_clear == 1'b0) else $error("bank_role_clear should be 0 during scrub");
        $display("Cycle 1: scrub_active=%b, cnt=%0d", scrub_active, dut.scrub_cnt);
        
        step(); // Cycle 2
        assert(scrub_active == 1'b1) else $error("scrub_active should be 1");
        $display("Cycle 2: scrub_active=%b, cnt=%0d", scrub_active, dut.scrub_cnt);
        
        step(); // Cycle 3
        assert(scrub_active == 1'b1) else $error("scrub_active should be 1");
        $display("Cycle 3: scrub_active=%b, cnt=%0d", scrub_active, dut.scrub_cnt);
        
        step(); // Cycle 4
        assert(scrub_active == 1'b1) else $error("scrub_active should be 1");
        $display("Cycle 4: scrub_active=%b, cnt=%0d", scrub_active, dut.scrub_cnt);
        
        step(); // Cycle 5 - scrub ends, clear pulses
        assert(scrub_active == 1'b0) else $error("scrub_active should be 0 after scrub");
        assert(bank_role_clear == 1'b1) else $error("bank_role_clear should pulse");
        assert(region_owner == 1'b1) else $error("region_owner should be committed");
        assert(role_tag == 2'b01) else $error("role_tag should be committed");
        $display("Cycle 5: scrub_active=%b, clear=%b, owner=%b, role=%b", 
                 scrub_active, bank_role_clear, region_owner, role_tag);
        
        step(); // Cycle 6 - clear deasserted
        assert(bank_role_clear == 1'b0) else $error("bank_role_clear should be 1-cycle pulse");
        $display("Cycle 6: clear=%b", bank_role_clear);
    endtask

    // Test scrub ignores new role_reassign during active scrub
    task automatic test_ignore_during_scrub();
        $display("\n=== TEST: Ignore New Reassign During Scrub ===");
        reset_dut();
        
        role_reassign = 1'b1;
        new_region_id = 1'b0;
        new_role = 2'b00;
        step();
        role_reassign = 1'b0;
        
        // Try to start another scrub during active scrub
        role_reassign = 1'b1;
        new_region_id = 1'b1;
        new_role = 2'b10;
        step();
        role_reassign = 1'b0;
        
        // Should continue original scrub (4 cycles total)
        step(); // 2
        step(); // 3
        step(); // 4
        step(); // 5 - should complete with original params
        assert(region_owner == 1'b0) else $error("Owner should be from first reassign");
        assert(role_tag == 2'b00) else $error("Role should be from first reassign");
        $display("After scrub: owner=%b, role=%b (first reassign params)", region_owner, role_tag);
    endtask

    // Test immediate reassign after scrub
    task automatic test_immediate_reassign();
        $display("\n=== TEST: Immediate Reassign After Scrub ===");
        reset_dut();
        
        // First scrub
        role_reassign = 1'b1;
        new_region_id = 1'b0;
        new_role = 2'b00;
        step();
        role_reassign = 1'b0;
        
        step(); step(); step(); step(); // Wait for scrub to complete
        
        // Immediately start second scrub
        role_reassign = 1'b1;
        new_region_id = 1'b1;
        new_role = 2'b10;
        step();
        role_reassign = 1'b0;
        
        assert(scrub_active == 1'b1) else $error("Second scrub should start");
        step(); step(); step(); step();
        assert(region_owner == 1'b1) else $error("Second owner should be committed");
        assert(role_tag == 2'b10) else $error("Second role should be committed");
        $display("Second scrub: owner=%b, role=%b", region_owner, role_tag);
    endtask

    initial begin
        $dumpfile("/root/research/mt_npu/tb/pod_bank_scrub_tb.vcd");
        $dumpvars(0, pod_bank_scrub_tb);

        test_basic_scrub();
        test_ignore_during_scrub();
        test_immediate_reassign();

        $display("\n=== ALL BANK SCRUB TESTS PASSED ===");
        $finish;
    end

endmodule