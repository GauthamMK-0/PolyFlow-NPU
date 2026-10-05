// test_split_partition.svh — TEST 1: Dispatch-Time Column Partitioning
// Included in hdf_top_tb.sv

task automatic run_test_split_partition();
    $display("\n--- [TEST 1] Dispatch-Time Column Split (Cols 0-1: A, Cols 2-3: B) ---");
    cfg_split_col     = 4'd2;
    cfg_update_strobe = 1;
    step_clk();
    cfg_update_strobe = 0;
    step_clk();

    $display("Region ID Mask = %b (Expected: 1100)", region_id_mask);
    if (region_id_mask !== 4'b1100) begin
        $display("ERROR: Split column decoding mismatch!");
        error_count++;
    end else begin
        $display("PASS: Split column decoded properly.");
    end
endtask
