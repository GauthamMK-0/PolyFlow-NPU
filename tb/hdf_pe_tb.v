module hdf_pe_tb;

    localparam int DATA_W      = 8;
    localparam int ACC_W       = 32;
    localparam int LIFETIME_W  = 4;
    localparam int REGION_W    = 1;

    logic clk;
    logic rst_n;

    logic [DATA_W-1:0] din_n, din_s, din_e, din_w;
    logic [DATA_W-1:0] dout_n, dout_s, dout_e, dout_w;
    logic [ACC_W-1:0]  acc_out;

    logic [1:0]        dataflow_mode;
    logic [REGION_W-1:0] region_id;
    logic                region_reassign;
    logic [3:0]          route_sel;
    logic                w_ld;
    logic                acc_clr;
    logic                lifetime_ld;
    logic [LIFETIME_W-1:0] lifetime_init;
    logic                bank_role_stale;
    logic                bank_role_clear;

    hdf_pe #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .LIFETIME_W(LIFETIME_W),
        .REGION_W(REGION_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .din_n(din_n),
        .din_s(din_s),
        .din_e(din_e),
        .din_w(din_w),
        .dout_n(dout_n),
        .dout_s(dout_s),
        .dout_e(dout_e),
        .dout_w(dout_w),
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
        .bank_role_clear(bank_role_clear)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Drive inputs on negedge, sample outputs on negedge
    task automatic tick();
        @(negedge clk);
    endtask

    task automatic reset_dut();
        rst_n = 0;
        din_n = '0; din_s = '0; din_e = '0; din_w = '0;
        dataflow_mode = 2'b00;
        region_id = '0;
        region_reassign = 1'b0;
        route_sel = 4'b0000;
        w_ld = 1'b0;
        acc_clr = 1'b0;
        lifetime_ld = 1'b0;
        lifetime_init = '0;
        bank_role_clear = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        tick();
        // Enable lifetime counter by default (large window)
        lifetime_ld = 1'b1;
        lifetime_init = 4'd15;
        tick();
        lifetime_ld = 1'b0;
        tick();
    endtask

    // WS mode test: weight stationary
    task automatic test_ws_mode();
        $display("\n=== TEST: WS Mode ===");
        reset_dut();
        dataflow_mode = 2'b00;
        route_sel = 4'b0011; // enable west (bit 0) and east (bit 1)
        w_ld = 1'b1;
        din_w = 8'sd5;  // weight = 5
        tick();
        w_ld = 1'b0;
        // Stream activations: 3, 4, 2
        din_e = 8'sd3;
        tick(); // acc = 5*3 = 15
        $display("Cycle 1: acc_out = %0d (expected 15)", acc_out);
        din_e = 8'sd4;
        tick(); // acc = 15 + 5*4 = 35
        $display("Cycle 2: acc_out = %0d (expected 35)", acc_out);
        din_e = 8'sd2;
        tick(); // acc = 35 + 5*2 = 45
        $display("Cycle 3: acc_out = %0d (expected 45)", acc_out);
        acc_clr = 1'b1;
        tick();
        acc_clr = 1'b0;
        $display("After acc_clr: acc_out = %0d (expected 0)", acc_out);
        assert(acc_out == 0) else $error("WS: acc_clr failed");
    endtask

    // IS mode test: input stationary
    task automatic test_is_mode();
        $display("\n=== TEST: IS Mode ===");
        reset_dut();
        dataflow_mode = 2'b10;
        route_sel = 4'b1010; // enable north (bit 3) and east (bit 1)
        w_ld = 1'b1;
        din_n = 8'sd7;  // input activation = 7
        tick();
        w_ld = 1'b0;
        // Stream weights: 2, 3, 1
        din_e = 8'sd2;
        tick(); // acc = 7*2 = 14
        $display("Cycle 1: acc_out = %0d (expected 14)", acc_out);
        din_e = 8'sd3;
        tick(); // acc = 14 + 7*3 = 35
        $display("Cycle 2: acc_out = %0d (expected 35)", acc_out);
        din_e = 8'sd1;
        tick(); // acc = 35 + 7*1 = 42
        $display("Cycle 3: acc_out = %0d (expected 42)", acc_out);
        assert(acc_out == 42) else $error("IS: accumulation mismatch");
    endtask

    // OS mode test: output stationary (Q*K^T)
    task automatic test_os_mode();
        $display("\n=== TEST: OS Mode ===");
        reset_dut();
        dataflow_mode = 2'b01;
        route_sel = 4'b1001; // enable north (bit 3, Q) and west (bit 0, K)
        // Q=3, K=4 -> acc = 12
        din_n = 8'sd3;
        din_w = 8'sd4;
        tick();
        $display("Cycle 1: acc_out = %0d (expected 12)", acc_out);
        // Q=2, K=5 -> acc = 12 + 10 = 22
        din_n = 8'sd2;
        din_w = 8'sd5;
        tick();
        $display("Cycle 2: acc_out = %0d (expected 22)", acc_out);
        // Q=-1, K=3 -> acc = 22 + (-3) = 19
        din_n = -8'sd1;
        din_w = 8'sd3;
        tick();
        $display("Cycle 3: acc_out = %0d (expected 19)", acc_out);
        assert(acc_out == 19) else $error("OS: signed accumulation mismatch");
    endtask

    // Lifetime counter test
    task automatic test_lifetime_counter();
        $display("\n=== TEST: Lifetime Counter ===");
        reset_dut();
        dataflow_mode = 2'b00;
        route_sel = 4'b0011; // west and east
        w_ld = 1'b1;
        din_w = 8'sd2;
        tick();
        w_ld = 1'b0;
        lifetime_ld = 1'b1;
        lifetime_init = 4'd3;
        tick();
        lifetime_ld = 1'b0;
        din_e = 8'sd5; // 2*5=10
        tick(); // lifetime=2, acc=10
        $display("Cycle 1: lifetime=%0d, acc=%0d", dut.lifetime_cnt, acc_out);
        din_e = 8'sd3; // 2*3=6
        tick(); // lifetime=1, acc=16
        $display("Cycle 2: lifetime=%0d, acc=%0d", dut.lifetime_cnt, acc_out);
        din_e = 8'sd7; // 2*7=14
        tick(); // lifetime=0, acc=30
        $display("Cycle 3: lifetime=%0d, acc=%0d", dut.lifetime_cnt, acc_out);
        din_e = 8'sd10; // should NOT accumulate (lifetime=0)
        tick();
        $display("Cycle 4: lifetime=%0d, acc=%0d (expected 30)", dut.lifetime_cnt, acc_out);
        assert(acc_out == 30) else $error("Lifetime: MAC should be gated after countdown");
    endtask

    // Bank role stale handshake test
    task automatic test_bank_role_stale();
        $display("\n=== TEST: Bank Role Stale Handshake ===");
        reset_dut();
        assert(bank_role_stale == 1'b0) else $error("Stale: initial should be 0");
        region_reassign = 1'b1;
        tick();
        region_reassign = 1'b0;
        assert(bank_role_stale == 1'b1) else $error("Stale: should be 1 after reassign");
        bank_role_clear = 1'b1;
        tick();
        bank_role_clear = 1'b0;
        assert(bank_role_stale == 1'b0) else $error("Stale: should be 0 after clear");
        $display("Stale handshake: PASS");
    endtask

    // Route sel gating test (disabled edges = signed zero)
    task automatic test_route_sel_gating();
        $display("\n=== TEST: Route Sel Gating ===");
        reset_dut();
        dataflow_mode = 2'b00;
        route_sel = 4'b0000; // all disabled
        w_ld = 1'b1;
        din_w = 8'sd10;
        tick();
        w_ld = 1'b0;
        din_e = 8'sd5;
        tick();
        $display("All disabled: acc_out = %0d (expected 0)", acc_out);
        assert(acc_out == 0) else $error("Route sel: disabled edges should contribute zero");
    endtask

    // Signed multiplication test
    task automatic test_signed_mult();
        $display("\n=== TEST: Signed Multiplication ===");
        reset_dut();
        dataflow_mode = 2'b01; // OS mode uses op_in_n * op_in_w
        route_sel = 4'b1001; // north and west
        // (-3) * 4 = -12
        din_n = -8'sd3;
        din_w = 8'sd4;
        tick();
        $display("Cycle 1: acc_out = %0d (expected -12)", $signed(acc_out));
        assert($signed(acc_out) == -12) else $error("Signed: (-3)*4 != -12");
        // (-5) * (-6) = 30 -> acc = -12 + 30 = 18
        din_n = -8'sd5;
        din_w = -8'sd6;
        tick();
        $display("Cycle 2: acc_out = %0d (expected 18)", $signed(acc_out));
        assert($signed(acc_out) == 18) else $error("Signed: (-5)*(-6) accumulation mismatch");
    endtask

    initial begin
        $dumpfile("/root/research/mt_npu/tb/hdf_pe_tb.vcd");
        $dumpvars(0, hdf_pe_tb);

        test_ws_mode();
        test_is_mode();
        test_os_mode();
        test_lifetime_counter();
        test_bank_role_stale();
        test_route_sel_gating();
        test_signed_mult();

        $display("\n=== ALL TESTS PASSED ===");
        $finish;
    end

endmodule