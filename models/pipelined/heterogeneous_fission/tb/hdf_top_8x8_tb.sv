// hdf_top_8x8_tb.sv — SystemVerilog Testbench for 8x8 Scaled Heterogeneous Fission Pod
// PolyFlow-NPU: 64 Processing Elements verification with Concurrent WS (CNN) and OS (Attention).

`timescale 1ns/1ps

module hdf_top_8x8_tb;

    localparam int DATA_W      = 8;
    localparam int ACC_W       = 32;
    localparam int LIFETIME_W  = 4;
    localparam int NUM_ROWS    = 8;
    localparam int NUM_COLS    = 8;
    localparam int NUM_BANKS   = 2;
    localparam int NUM_REGIONS = 2;
    localparam int REGION_W    = 1;
    localparam int BW_W        = 8;
    localparam int SPLIT_W     = 4;

    logic clk;
    logic rst_n;

    logic [SPLIT_W-1:0]                 cfg_split_col;
    logic                               cfg_update_strobe;

    logic [2*NUM_REGIONS-1:0]           phase_tag;
    logic [NUM_BANKS-1:0]               token_req_A;
    logic [NUM_BANKS-1:0]               token_req_B;
    logic [NUM_BANKS-1:0]               token_release_A;
    logic [NUM_BANKS-1:0]               token_release_B;
    logic [NUM_BANKS-1:0]               role_reassign;
    logic [NUM_BANKS-1:0]               new_region_id_per_bank;
    logic [2*NUM_BANKS-1:0]             new_role_per_bank;

    logic [2*NUM_REGIONS-1:0]           dataflow_mode;
    logic [NUM_REGIONS-1:0]             lifetime_ld;
    logic [NUM_REGIONS*LIFETIME_W-1:0]  lifetime_init;
    logic [NUM_REGIONS-1:0]             w_ld;
    logic [NUM_REGIONS-1:0]             acc_clr;

    logic [NUM_COLS*DATA_W-1:0]         din_n;
    logic [NUM_ROWS*DATA_W-1:0]         din_w_region_a;
    logic [NUM_ROWS*DATA_W-1:0]         din_w_region_b;

    /* verilator lint_off UNUSEDSIGNAL */
    wire  [NUM_COLS*DATA_W-1:0]         dout_s;
    wire  [NUM_ROWS*DATA_W-1:0]         dout_e;
    wire  [NUM_REGIONS-1:0]             reconfig_urgent;
    wire  [NUM_BANKS-1:0]               scrub_active_bus;
    wire  [NUM_BANKS-1:0]               bank_role_clear_bus;
    wire  [NUM_BANKS*NUM_REGIONS-1:0]   token_grant_bus;
    wire  [NUM_BANKS-1:0]               token_held_bus;
    wire  [NUM_BANKS*REGION_W-1:0]      token_owner_bus;
    wire  [NUM_BANKS*REGION_W-1:0]      bank_owner_bus;
    wire  [NUM_BANKS*2-1:0]             bank_role_tag_bus;
    wire  [NUM_COLS-1:0]                pe_bank_role_stale_bus;
    /* verilator lint_on UNUSEDSIGNAL */

    wire  [NUM_ROWS*NUM_COLS*ACC_W-1:0] acc_out_flat;
    wire  [NUM_REGIONS*BW_W-1:0]        bw_alloc;
    wire  [NUM_COLS-1:0]                region_id_mask;

    int error_count = 0;

    function automatic logic signed [ACC_W-1:0] get_pe_acc(int r, int c);
        return acc_out_flat[(r*NUM_COLS + c)*ACC_W +: ACC_W];
    endfunction

    task automatic set_din_n(int c, logic [DATA_W-1:0] val);
        din_n[c*DATA_W +: DATA_W] = val;
    endtask

    task automatic set_din_w_a(int r, logic [DATA_W-1:0] val);
        din_w_region_a[r*DATA_W +: DATA_W] = val;
    endtask

    task automatic set_din_w_b(int r, logic [DATA_W-1:0] val);
        din_w_region_b[r*DATA_W +: DATA_W] = val;
    endtask

    // DUT Instantiation
    hdf_top_8x8 #(
        .DATA_W     (DATA_W),
        .ACC_W      (ACC_W),
        .LIFETIME_W (LIFETIME_W),
        .NUM_ROWS   (NUM_ROWS),
        .NUM_COLS   (NUM_COLS),
        .NUM_BANKS  (NUM_BANKS),
        .NUM_REGIONS(NUM_REGIONS),
        .REGION_W   (REGION_W),
        .BW_W       (BW_W),
        .SPLIT_W    (SPLIT_W)
    ) dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .cfg_split_col          (cfg_split_col),
        .cfg_update_strobe      (cfg_update_strobe),
        .phase_tag              (phase_tag),
        .token_req_A            (token_req_A),
        .token_req_B            (token_req_B),
        .token_release_A        (token_release_A),
        .token_release_B        (token_release_B),
        .role_reassign          (role_reassign),
        .new_region_id_per_bank (new_region_id_per_bank),
        .new_role_per_bank      (new_role_per_bank),
        .dataflow_mode          (dataflow_mode),
        .lifetime_ld            (lifetime_ld),
        .lifetime_init          (lifetime_init),
        .w_ld                   (w_ld),
        .acc_clr                (acc_clr),
        .din_n                  (din_n),
        .din_w_region_a         (din_w_region_a),
        .din_w_region_b         (din_w_region_b),
        .dout_s                 (dout_s),
        .dout_e                 (dout_e),
        .acc_out_flat           (acc_out_flat),
        .bw_alloc               (bw_alloc),
        .reconfig_urgent        (reconfig_urgent),
        .region_id_mask         (region_id_mask),
        .scrub_active_bus       (scrub_active_bus),
        .bank_role_clear_bus    (bank_role_clear_bus),
        .token_grant_bus        (token_grant_bus),
        .token_held_bus         (token_held_bus),
        .token_owner_bus        (token_owner_bus),
        .bank_owner_bus         (bank_owner_bus),
        .bank_role_tag_bus      (bank_role_tag_bus),
        .pe_bank_role_stale_bus (pe_bank_role_stale_bus)
    );

    initial clk = 0;
    always #5 clk <= ~clk;

    task automatic step_clk();
        @(posedge clk);
        #1;
    endtask

    task automatic reset_dut();
        rst_n                  = 0;
        cfg_split_col          = 4'd4; // Split 8-col array symmetrically at column 4
        cfg_update_strobe      = 0;
        phase_tag              = {2'b01, 2'b01};
        token_req_A            = '0;
        token_req_B            = '0;
        token_release_A        = '0;
        token_release_B        = '0;
        role_reassign          = '0;
        new_region_id_per_bank = '0;
        new_role_per_bank      = '0;
        dataflow_mode          = {2'b01, 2'b00}; // Reg B: OS, Reg A: WS
        lifetime_ld            = 2'b00;
        lifetime_init          = '0;
        w_ld                   = 2'b00;
        acc_clr                = 2'b11;
        din_n                  = '0;
        din_w_region_a         = '0;
        din_w_region_b         = '0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        step_clk();
        acc_clr = 2'b00;
        step_clk();
    endtask

    initial begin
        $display("================================================================");
        $display(" [TESTSUITE] Starting 8x8 Scaled Heterogeneous Fission Tests");
        $display("================================================================");

        reset_dut();

        // TEST 1: Dispatch-Time Column Partitioning
        $display("\n--- [TEST 1] 8x8 Column Split (Cols 0-3: A, Cols 4-7: B) ---");
        cfg_split_col     = 4'd4;
        cfg_update_strobe = 1;
        step_clk();
        cfg_update_strobe = 0;
        step_clk();

        $display("Region ID Mask = %b (Expected: 11110000)", region_id_mask);
        if (region_id_mask !== 8'b11110000) begin
            $display("ERROR: 8x8 split column decoding mismatch!");
            error_count++;
        end else begin
            $display("PASS: 8x8 split column decoded properly.");
        end

        // TEST 2: Concurrent Heterogeneous Co-Execution: Reg A (WS) + Reg B (OS)
        $display("\n--- [TEST 2] 8x8 Co-Execution: Reg A (WS) + Reg B (OS) ---");
        acc_clr = 2'b11;
        dataflow_mode = {2'b01, 2'b00}; // Reg B: OS (01), Reg A: WS (00)
        step_clk();
        acc_clr = 2'b00;

        // Preload weights for Region A (WS) & initialize lifetime counter for both
        w_ld[0]          = 1'b1;
        lifetime_ld      = 2'b11;
        lifetime_init    = {4'd15, 4'd15};
        for (int r = 0; r < NUM_ROWS; r++) begin
            set_din_w_a(r, 8'd5); // Stationary weight = 5
        end
        step_clk();
        w_ld[0]     = 1'b0;
        lifetime_ld = 2'b00;

        // Cycle 1: Region A (x=3 -> 5*3=15); Region B (Q=4, K=7 -> 28)
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
        for (int c = 4; c < NUM_COLS; c++) set_din_n(c, 8'd4);
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_b(r, 8'd7);
        step_clk();

        // Cycle 2: Region A (x=3 -> 15+15=30); Region B (Q=2, K=6 -> 12, acc=28+12=40)
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
        for (int c = 4; c < NUM_COLS; c++) set_din_n(c, 8'd2);
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_b(r, 8'd6);
        step_clk();

        // Cycle 3: Region A (x=3 -> 30+15=45); Region B stops inputs
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
        for (int c = 4; c < NUM_COLS; c++) set_din_n(c, 8'd0);
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_b(r, 8'd0);
        step_clk();

        // Cycle 4: Region A (x=3 -> 45+15=60)
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
        step_clk();
        step_clk(); // Drain pipeline stage

        $display("8x8 Reg A (WS, PE[0][0]) = %0d, PE[7][0] = %0d (Expected: 60)", get_pe_acc(0,0), get_pe_acc(7,0));
        $display("8x8 Reg B (OS, PE[0][4]) = %0d, PE[7][4] = %0d (Expected: 40)", get_pe_acc(0,4), get_pe_acc(7,4));

        if (get_pe_acc(0,0) !== 32'd60 || get_pe_acc(7,0) !== 32'd60 ||
            get_pe_acc(0,4) !== 32'd40 || get_pe_acc(7,4) !== 32'd40) begin
            $display("ERROR: 8x8 heterogeneous co-execution mismatch!");
            error_count++;
        end else begin
            $display("PASS: 8x8 Reg A (WS) and Reg B (OS) executed concurrently with correct math!");
        end

        // TEST 3: EPPA Bandwidth Arbitration
        $display("\n--- [TEST 3] 8x8 EPPA Dynamic Bandwidth Arbitration ---");
        phase_tag = {2'b10, 2'b00}; // Reg B (STREAM), Reg A (BURST)
        step_clk();

        $display("BW Alloc: Reg A = 0x%0h (Exp: 0xFF), Reg B = 0x%0h (Exp: 0x7F)",
                 bw_alloc[0 +: BW_W], bw_alloc[BW_W +: BW_W]);

        if (bw_alloc[0 +: BW_W] !== 8'hFF || bw_alloc[BW_W +: BW_W] !== 8'h7F) begin
            $display("ERROR: 8x8 EPPA bandwidth allocation mismatch!");
            error_count++;
        end else begin
            $display("PASS: 8x8 EPPA dynamic allocation verified.");
        end

        // TEST 4: Shared Memory Migration (Bank 0 -> Region B)
        $display("\n--- [TEST 4] 8x8 Shared Memory Bank Scrubbing ---");
        role_reassign[0]          = 1'b1;
        new_region_id_per_bank[0] = 1'b1; // Assign to Region B
        new_role_per_bank[0 +: 2] = 2'b01;
        step_clk();
        role_reassign[0]          = 1'b0;

        repeat (3) step_clk();
        step_clk(); // Complete cycle 4

        $display("8x8 Bank 0 Scrub Completed: bank_role_clear = %b", bank_role_clear_bus[0]);
        if (bank_role_clear_bus[0] !== 1'b1) begin
            $display("ERROR: Expected bank_role_clear pulse upon scrub completion!");
            error_count++;
        end else begin
            $display("PASS: 8x8 memory bank scrub zeroing sequence verified.");
        end

        // Summary
        $display("\n================================================================");
        if (error_count == 0) begin
            $display(" [SUCCESS] ALL 8x8 HETEROGENEOUS FISSION TESTS PASSED (Errors: 0)");
            $display("================================================================");
            $finish(0);
        end else begin
            $display(" [FAILED] 8x8 HETEROGENEOUS FISSION TESTS ENCOUNTERED %0d ERRORS", error_count);
            $display("================================================================");
            $finish(1);
        end
    end

endmodule
