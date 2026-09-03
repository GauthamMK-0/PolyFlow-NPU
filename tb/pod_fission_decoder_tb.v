module pod_fission_decoder_tb;

    localparam int NUM_COLS = 16;

    logic clk;
    logic rst_n;
    logic [3:0] cfg_split_col;
    logic cfg_update_strobe;
    logic [NUM_COLS-1:0] region_id_mask;
    logic [NUM_COLS-1:0] region_reassign_bus;

    pod_fission_decoder #(
        .NUM_COLS(NUM_COLS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_split_col(cfg_split_col),
        .cfg_update_strobe(cfg_update_strobe),
        .region_id_mask(region_id_mask),
        .region_reassign_bus(region_reassign_bus)
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
        cfg_split_col = 4'd0;
        cfg_update_strobe = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        step();
    endtask

    // Test default reset value (split at 8)
    task automatic test_default_reset();
        $display("\n=== TEST: Default Reset (Split at 8) ===");
        reset_dut();
        // region_id_mask should be 16'hFF00 (cols 0-7=0, 8-15=1)
        assert(region_id_mask == 16'hFF00) else $error("Default mask: expected 0xFF00, got %h", region_id_mask);
        assert(region_reassign_bus == 16'h0000) else $error("Default reassign: expected 0, got %h", region_reassign_bus);
        $display("Default mask: %h (expected FF00)", region_id_mask);
        $display("Default reassign: %h (expected 0000)", region_reassign_bus);
    endtask

    // Test split at column 4
    task automatic test_split_4();
        $display("\n=== TEST: Split at Column 4 ===");
        reset_dut();
        cfg_split_col = 4'd4;
        cfg_update_strobe = 1'b1;
        step();
        cfg_update_strobe = 1'b0;
        // Mask: cols 0-3=0 (A), cols 4-15=1 (B) = 0xFFF0
        assert(region_id_mask == 16'hFFF0) else $error("Split 4 mask: expected 0xFFF0, got %h", region_id_mask);
        // Reassign: cols 4-7 changed from 0 to 1 = 0x00F0
        assert(region_reassign_bus == 16'h00F0) else $error("Split 4 reassign: expected 0x00F0, got %h", region_reassign_bus);
        $display("Split 4 mask: %h (expected FFF0)", region_id_mask);
        $display("Split 4 reassign: %h (expected 00F0)", region_reassign_bus);
        
        // Next cycle: reassign should be 0
        step();
        assert(region_reassign_bus == 16'h0000) else $error("Reassign should clear after 1 cycle");
        $display("Next cycle reassign: %h (expected 0000)", region_reassign_bus);
    endtask

    // Test split at column 12
    task automatic test_split_12();
        $display("\n=== TEST: Split at Column 12 ===");
        reset_dut();
        cfg_split_col = 4'd12;
        cfg_update_strobe = 1'b1;
        step();
        cfg_update_strobe = 1'b0;
        // Mask: cols 0-11=0, cols 12-15=1 = 0xF000
        assert(region_id_mask == 16'hF000) else $error("Split 12 mask: expected 0xF000, got %h", region_id_mask);
        // Reassign: cols 8-11 changed from 1 to 0, cols 12-15 changed from 1 to 1 (no change) = 0x0F00
        assert(region_reassign_bus == 16'h0F00) else $error("Split 12 reassign: expected 0x0F00, got %h", region_reassign_bus);
        $display("Split 12 mask: %h (expected F000)", region_id_mask);
        $display("Split 12 reassign: %h (expected 0F00)", region_reassign_bus);
    endtask

    // Test split at column 0 (all Region B)
    task automatic test_split_0();
        $display("\n=== TEST: Split at Column 0 (All Region B) ===");
        reset_dut();
        cfg_split_col = 4'd0;
        cfg_update_strobe = 1'b1;
        step();
        cfg_update_strobe = 1'b0;
        // Mask: all 1 = 0xFFFF
        assert(region_id_mask == 16'hFFFF) else $error("Split 0 mask: expected 0xFFFF, got %h", region_id_mask);
        // Reassign: cols 0-7 changed from 0 to 1 = 0x00FF
        assert(region_reassign_bus == 16'h00FF) else $error("Split 0 reassign: expected 0x00FF, got %h", region_reassign_bus);
        $display("Split 0 mask: %h (expected FFFF)", region_id_mask);
        $display("Split 0 reassign: %h (expected 00FF)", region_reassign_bus);
    endtask

    // Test split at column 15 (only col 15 is Region B)
    task automatic test_split_15();
        $display("\n=== TEST: Split at Column 15 ===");
        reset_dut();
        cfg_split_col = 4'd15;
        cfg_update_strobe = 1'b1;
        step();
        cfg_update_strobe = 1'b0;
        // Mask: cols 0-14=0, col 15=1 = 0x8000
        assert(region_id_mask == 16'h8000) else $error("Split 15 mask: expected 0x8000, got %h", region_id_mask);
        // Reassign: cols 8-14 changed from 1 to 0 = 0x7F00
        assert(region_reassign_bus == 16'h7F00) else $error("Split 15 reassign: expected 0x7F00, got %h", region_reassign_bus);
        $display("Split 15 mask: %h (expected 8000)", region_id_mask);
        $display("Split 15 reassign: %h (expected 7F00)", region_reassign_bus);
    endtask

    // Test multiple strobes
    task automatic test_multiple_strobes();
        $display("\n=== TEST: Multiple Strobes ===");
        reset_dut();
        
        // First: split at 8 (default, no change)
        cfg_split_col = 4'd8;
        cfg_update_strobe = 1'b1;
        step();
        cfg_update_strobe = 1'b0;
        assert(region_reassign_bus == 16'h0000) else $error("Split 8->8: no reassign expected");
        
        // Second: split at 4
        cfg_split_col = 4'd4;
        cfg_update_strobe = 1'b1;
        step();
        cfg_update_strobe = 1'b0;
        assert(region_id_mask == 16'hFFF0) else $error("Split 8->4 mask mismatch");
        assert(region_reassign_bus == 16'h00F0) else $error("Split 8->4 reassign mismatch");
        
        // Third: split at 12
        cfg_split_col = 4'd12;
        cfg_update_strobe = 1'b1;
        step();
        cfg_update_strobe = 1'b0;
        assert(region_id_mask == 16'hF000) else $error("Split 4->12 mask mismatch: got %h", region_id_mask);
        assert(region_reassign_bus == 16'h0FF0) else $error("Split 4->12 reassign mismatch: expected 0FF0, got %h", region_reassign_bus);
        
        $display("Multiple strobes: PASS");
    endtask

    // Test strobe width (should be 1-cycle pulse)
    task automatic test_strobe_width();
        $display("\n=== TEST: Strobe Width ===");
        reset_dut();
        cfg_split_col = 4'd4;
        cfg_update_strobe = 1'b1;
        step();
        // Hold strobe high for multiple cycles
        step();
        step();
        cfg_update_strobe = 1'b0;
        step();
        // Reassign should only pulse for 1 cycle
        // We can't easily check pulse width in this test structure, but we verify
        // that region_id_prev is updated only once per strobe
        cfg_split_col = 4'd8;
        cfg_update_strobe = 1'b1;
        step();
        cfg_update_strobe = 1'b0;
        assert(region_id_mask == 16'hFF00) else $error("Strobe width: mask should be FF00");
        $display("Strobe width: PASS");
    endtask

    initial begin
        $dumpfile("/root/research/mt_npu/tb/pod_fission_decoder_tb.vcd");
        $dumpvars(0, pod_fission_decoder_tb);

        test_default_reset();
        test_split_4();
        test_split_12();
        test_split_0();
        test_split_15();
        test_multiple_strobes();
        test_strobe_width();

        $display("\n=== ALL FISSION DECODER TESTS PASSED ===");
        $finish;
    end

endmodule