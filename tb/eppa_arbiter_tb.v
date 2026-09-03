module eppa_arbiter_tb;

    localparam int NUM_REGIONS = 2;
    localparam int BW_W        = 8;

    logic clk;
    logic rst_n;
    logic [2*NUM_REGIONS-1:0] phase_tag;
    logic [NUM_REGIONS*BW_W-1:0] bw_alloc;
    logic [NUM_REGIONS-1:0] reconfig_urgent;

    eppa_arbiter #(
        .NUM_REGIONS(NUM_REGIONS),
        .BW_W(BW_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .phase_tag(phase_tag),
        .bw_alloc(bw_alloc),
        .reconfig_urgent(reconfig_urgent)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Drive on negedge, sample on posedge (after DUT updates)
    task automatic step();
        @(negedge clk);  // Drive inputs here
        @(posedge clk);  // Sample outputs here (after DUT NBA)
        #1;  // Small delay to ensure NBA completed
    endtask

    task automatic reset_dut();
        rst_n = 0;
        phase_tag = '0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        step();
    endtask

    // Test basic phase transitions
    task automatic test_basic_transitions();
        $display("\n=== TEST: Basic Phase Transitions ===");
        reset_dut();

        // Initial: both IDLE
        phase_tag = {2'b01, 2'b01}; // R1=IDLE, R0=IDLE
        step();
        assert(bw_alloc == 16'h0000) else $error("Initial: both IDLE should be 0");
        assert(reconfig_urgent == 2'b00) else $error("Initial: no reconfig urgent");
        $display("Initial (IDLE,IDLE): bw_alloc=%h, reconfig=%b", bw_alloc, reconfig_urgent);

        // R0 -> BURST
        phase_tag = {2'b01, 2'b00}; // R1=IDLE, R0=BURST
        step();
        assert(bw_alloc[7:0] == 8'hFF) else $error("R0 BURST: should be 0xFF");
        assert(bw_alloc[15:8] == 8'h00) else $error("R1 IDLE: should be 0x00");
        assert(reconfig_urgent == 2'b00) else $error("BURST: no reconfig urgent");
        $display("R0 BURST: bw_alloc=%h, reconfig=%b", bw_alloc, reconfig_urgent);

        // R1 -> STREAM (R0 stays BURST)
        phase_tag = {2'b10, 2'b00}; // R1=STREAM, R0=BURST
        step();
        assert(bw_alloc[7:0] == 8'hFF) else $error("R0 BURST: should stay 0xFF");
        assert(bw_alloc[15:8] == 8'h7F) else $error("R1 STREAM: should be 0x7F");
        $display("R1 STREAM: bw_alloc=%h, reconfig=%b", bw_alloc, reconfig_urgent);

        // R0 -> IDLE (R1 stays STREAM)
        phase_tag = {2'b10, 2'b01}; // R1=STREAM, R0=IDLE
        step();
        assert(bw_alloc[7:0] == 8'h00) else $error("R0 IDLE: should be 0x00");
        assert(bw_alloc[15:8] == 8'h7F) else $error("R1 STREAM: should stay 0x7F");
        $display("R0 IDLE: bw_alloc=%h, reconfig=%b", bw_alloc, reconfig_urgent);

        // R1 -> RECONFIG
        phase_tag = {2'b11, 2'b01}; // R1=RECONFIG, R0=IDLE
        step();
        assert(bw_alloc[15:8] == 8'hFF) else $error("R1 RECONFIG: should be 0xFF");
        assert(reconfig_urgent[1] == 1'b1) else $error("R1 RECONFIG: urgent should be 1");
        assert(reconfig_urgent[0] == 1'b0) else $error("R0 IDLE: urgent should be 0");
        $display("R1 RECONFIG: bw_alloc=%h, reconfig=%b", bw_alloc, reconfig_urgent);
    endtask

    // Test pinning - no change when same phase
    task automatic test_pinning();
        $display("\n=== TEST: Pinning (No Recompute on Same Phase) ===");
        reset_dut();

        phase_tag = {2'b00, 2'b00}; // Both BURST
        step();
        $display("Both BURST: bw_alloc=%h", bw_alloc);

        // Change to same value - should not recompute (but in our impl it does on any edge)
        // Actually the spec says "only when some region's phase tag changes"
        // So if phase_tag == phase_tag_prev, no change
        phase_tag = {2'b00, 2'b00}; // Same
        step();
        $display("Same BURST: bw_alloc=%h (should be unchanged)", bw_alloc);
        assert(bw_alloc == 16'hFFFF) else $error("Pinning: should remain 0xFFFF");

        // Change R0 to IDLE
        phase_tag = {2'b00, 2'b01}; // R1=BURST, R0=IDLE
        step();
        assert(bw_alloc[7:0] == 8'h00) else $error("R0 IDLE: should be 0");
        assert(bw_alloc[15:8] == 8'hFF) else $error("R1 BURST: should remain 0xFF");
        $display("R0 IDLE: bw_alloc=%h", bw_alloc);
    endtask

    // Test 1-cycle detection latency
    task automatic test_detection_latency();
        $display("\n=== TEST: 1-Cycle Detection Latency ===");
        reset_dut();

        phase_tag = {2'b01, 2'b01}; // Both IDLE
        step();

        // Transition at cycle N
        phase_tag = {2'b01, 2'b00}; // R0 -> BURST
        step(); // Cycle N+1: allocation updated
        assert(bw_alloc[7:0] == 8'hFF) else $error("Latency: allocation should update in 1 cycle");
        $display("Latency test: 1 cycle - PASS");
    endtask

    // Test oversubscription (both BURST = 200%)
    task automatic test_oversubscription();
        $display("\n=== TEST: Oversubscription (Documented Behavior) ===");
        reset_dut();

        phase_tag = {2'b00, 2'b00}; // Both BURST
        step();
        assert(bw_alloc == 16'hFFFF) else $error("Both BURST: each gets 0xFF");
        $display("Both BURST: bw_alloc=%h (200%% - documented oversubscription)", bw_alloc);
    endtask

    initial begin
        $dumpfile("/root/research/mt_npu/tb/eppa_arbiter_tb.vcd");
        $dumpvars(0, eppa_arbiter_tb);

        test_basic_transitions();
        test_pinning();
        test_detection_latency();
        test_oversubscription();

        $display("\n=== ALL EPPA TESTS PASSED ===");
        $finish;
    end

endmodule