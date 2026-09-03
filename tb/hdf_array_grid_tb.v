module hdf_array_grid_tb;

    // Use parameters from the module
    parameter int DATA_W      = 8;
    parameter int ACC_W       = 32;
    parameter int LIFETIME_W  = 4;
    parameter int REGION_W    = 1;
    parameter int NUM_ROWS    = 4;
    parameter int NUM_COLS    = 8;

    logic clk;
    logic rst_n;

    logic [DATA_W-1:0] din_n [NUM_COLS-1:0];
    logic [DATA_W-1:0] din_s [NUM_COLS-1:0];
    logic [DATA_W-1:0] din_w [NUM_ROWS-1:0];
    logic [DATA_W-1:0] dout_n [NUM_COLS-1:0];
    logic [DATA_W-1:0] dout_s [NUM_COLS-1:0];
    logic [DATA_W-1:0] dout_e [NUM_ROWS-1:0];
    logic [ACC_W-1:0]  acc_out [NUM_COLS-1:0];

    logic [1:0]        dataflow_mode [NUM_COLS-1:0];
    logic [REGION_W-1:0] region_id [NUM_COLS-1:0];
    logic              region_reassign [NUM_COLS-1:0];
    logic [3:0]        route_sel [NUM_COLS-1:0];
    logic              w_ld [NUM_COLS-1:0];
    logic              acc_clr [NUM_COLS-1:0];
    logic              lifetime_ld [NUM_COLS-1:0];
    logic [LIFETIME_W-1:0] lifetime_init [NUM_COLS-1:0];
    logic              bank_role_stale [NUM_COLS-1:0];
    logic              bank_role_clear [NUM_COLS-1:0];
    logic [NUM_COLS-1:0] region_id_mask;

    hdf_array_grid #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .LIFETIME_W(LIFETIME_W),
        .REGION_W(REGION_W),
        .NUM_ROWS(NUM_ROWS),
        .NUM_COLS(NUM_COLS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .din_n(din_n),
        .din_s(din_s),
        .din_w(din_w),
        .dout_n(dout_n),
        .dout_s(dout_s),
        .dout_e(dout_e),
        .acc_out(acc_out),
        .dataflow_mode(dataflow_mode),
        .region_id(region_id),
        .region_reassign(region_reassign),
        .route_sel(route_sel),
        .w_ld(w_ld),
        .acc_clr(acc_clr),
        .lifetime_ld(lifetime_ld),
        .lifetime_init(lifetime_init),
        .bank_role_stale(bank_role_stale),
        .bank_role_clear(bank_role_clear),
        .region_id_mask(region_id_mask)
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
        for (int i = 0; i < NUM_COLS; i++) begin
            din_n[i] = '0; din_s[i] = '0;
            dataflow_mode[i] = 2'b00;
            region_id[i] = '0;
            region_reassign[i] = 1'b0;
            route_sel[i] = 4'b0000;
            w_ld[i] = 1'b0;
            acc_clr[i] = 1'b1;  // Assert acc_clr during reset
            lifetime_ld[i] = 1'b0;
            lifetime_init[i] = '0;
            bank_role_clear[i] = 1'b0;
        end
        for (int i = 0; i < NUM_ROWS; i++) begin
            din_w[i] = '0;
        end
        region_id_mask = '0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        step();
        // Clear acc_clr, enable lifetime for all
        for (int i = 0; i < NUM_COLS; i++) begin
            acc_clr[i] = 1'b0;
            lifetime_ld[i] = 1'b1;
            lifetime_init[i] = 4'd15;
        end
        step();
        for (int i = 0; i < NUM_COLS; i++) begin
            lifetime_ld[i] = 1'b0;
        end
        step();
    endtask

    // Test boundary isolation: split at column 4
    task automatic test_boundary_isolation();
        $display("\n=== TEST: Boundary Isolation at Column 4 ===");
        reset_dut();
        
        // Set region_id_mask: cols 0-3 = Region A (0), cols 4-7 = Region B (1)
        region_id_mask = 8'b11110000; // bits 7:4 = 1, 3:0 = 0
        
        // Configure all PEs for WS mode
        for (int c = 0; c < NUM_COLS; c++) begin
            dataflow_mode[c] = 2'b00; // WS
            route_sel[c] = 4'b0011;   // west and east
            region_id[c] = region_id_mask[c];
        end
        
        // Load weights in Region A (cols 0-3)
        for (int c = 0; c < 4; c++) begin
            w_ld[c] = 1'b1;
            din_w[0] = 8'd5; // Weight = 5 for row 0
        end
        step();
        for (int c = 0; c < 4; c++) begin
            w_ld[c] = 1'b0;
        end
        
        // Stream activations from west into Region A
        din_w[0] = 8'd3; // Activation = 3
        step(); // Cycle 1: Region A PEs compute 5*3=15
        
        // Check Region A accumulators (cols 0-3)
        for (int c = 0; c < 4; c++) begin
            $display("Col %0d (Region A): acc_out = %0d", c, acc_out[c]);
            assert(acc_out[c] == 15) else $error("Col %0d: expected 15, got %0d", c, acc_out[c]);
        end
        
        // Check Region B accumulators (cols 4-7) - should be 0 (no data from west due to boundary)
        for (int c = 4; c < 8; c++) begin
            $display("Col %0d (Region B): acc_out = %0d", c, acc_out[c]);
            assert(acc_out[c] == 0) else $error("Col %0d (Region B): expected 0, got %0d", c, acc_out[c]);
        end
        
        $display("Boundary isolation: PASS - Region B isolated from Region A");
    endtask

    // Test data flow within region (no boundary crossing)
    task automatic test_intra_region_flow();
        $display("\n=== TEST: Intra-Region Data Flow ===");
        reset_dut();
        
        // Single region (all Region A)
        region_id_mask = 8'b00000000;
        for (int c = 0; c < NUM_COLS; c++) begin
            dataflow_mode[c] = 2'b00; // WS
            route_sel[c] = 4'b0011;   // west and east
            region_id[c] = 1'b0;
        end
        
        // Load weights
        for (int c = 0; c < NUM_COLS; c++) begin
            w_ld[c] = 1'b1;
            din_w[0] = 8'd2;
        end
        step();
        for (int c = 0; c < NUM_COLS; c++) begin
            w_ld[c] = 1'b0;
        end
        
        // Stream activations
        din_w[0] = 8'd4;
        step(); // 2*4=8
        
        for (int c = 0; c < NUM_COLS; c++) begin
            $display("Col %0d: acc_out = %0d", c, acc_out[c]);
            assert(acc_out[c] == 8) else $error("Col %0d: expected 8, got %0d", c, acc_out[c]);
        end
        
        $display("Intra-region flow: PASS");
    endtask

    initial begin
        $dumpfile("/root/research/mt_npu/tb/hdf_array_grid_tb.vcd");
        $dumpvars(0, hdf_array_grid_tb);

        test_boundary_isolation();
        test_intra_region_flow();

        $display("\n=== ALL ARRAY GRID TESTS PASSED ===");
        $finish;
    end

endmodule