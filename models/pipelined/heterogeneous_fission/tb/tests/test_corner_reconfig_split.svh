// test_corner_reconfig_split.svh — TEST: Dynamic Reconfiguration & Boundary Partitioning
// Verifies runtime array fission across all boundary split columns: 0, 1, 2, 3, 4.

task automatic run_test_corner_reconfig_split();
    $display("\n--- [TEST: CORNER] Dynamic Reconfiguration Across All Split Boundaries ---");

    // Test 1: Full Region B allocation (Split Col = 0 -> All cols belong to Region B)
    cfg_split_col     = 4'd0;
    cfg_update_strobe = 1'b1;
    step_clk();
    cfg_update_strobe = 1'b0;
    step_clk();
    $display("Split Col 0 (All B): region_id_mask = %04b (Expected: 1111)", region_id_mask);
    if (region_id_mask !== 4'b1111) begin
        $display("ERROR: Split column 0 failed to assign all columns to Region B!");
        error_count++;
    end else begin
        $display("PASS: All-Region-B partition verified.");
    end

    // Test 2: Asymmetric Split 1:3 (Col 0: Reg A, Cols 1-3: Reg B)
    cfg_split_col     = 4'd1;
    cfg_update_strobe = 1'b1;
    step_clk();
    cfg_update_strobe = 1'b0;
    step_clk();
    $display("Split Col 1 (Asym 1:3): region_id_mask = %04b (Expected: 1110)", region_id_mask);
    if (region_id_mask !== 4'b1110) begin
        $display("ERROR: Split column 1 failed to assign 1:3 partition!");
        error_count++;
    end else begin
        $display("PASS: Asymmetric 1:3 partition verified.");
    end

    // Test 3: Asymmetric Split 3:1 (Cols 0-2: Reg A, Col 3: Reg B)
    cfg_split_col     = 4'd3;
    cfg_update_strobe = 1'b1;
    step_clk();
    cfg_update_strobe = 1'b0;
    step_clk();
    $display("Split Col 3 (Asym 3:1): region_id_mask = %04b (Expected: 1000)", region_id_mask);
    if (region_id_mask !== 4'b1000) begin
        $display("ERROR: Split column 3 failed to assign 3:1 partition!");
        error_count++;
    end else begin
        $display("PASS: Asymmetric 3:1 partition verified.");
    end

    // Test 4: Full Region A allocation (Split Col = 4 -> All cols belong to Region A)
    cfg_split_col     = 4'd4;
    cfg_update_strobe = 1'b1;
    step_clk();
    cfg_update_strobe = 1'b0;
    step_clk();
    $display("Split Col 4 (All A): region_id_mask = %04b (Expected: 0000)", region_id_mask);
    if (region_id_mask !== 4'b0000) begin
        $display("ERROR: Split column 4 failed to assign all columns to Region A!");
        error_count++;
    end else begin
        $display("PASS: All-Region-A partition verified.");
    end

    // Restore symmetric split (Cols 0-1: A, Cols 2-3: B)
    cfg_split_col     = 4'd2;
    cfg_update_strobe = 1'b1;
    step_clk();
    cfg_update_strobe = 1'b0;
    step_clk();
endtask
