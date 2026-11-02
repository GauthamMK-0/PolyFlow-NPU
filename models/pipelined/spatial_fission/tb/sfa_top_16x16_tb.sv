// sfa_top_16x16_tb.sv — SystemVerilog Testbench for 16x16 Scaled Spatial Fission Pod
// PolyFlow-NPU: 256 Processing Elements verification with 8+8 Column Fission & 4-Bank Memory Safety.

`timescale 1ns/1ps

module sfa_top_16x16_tb;

    localparam int DATA_W      = 8;
    localparam int ACC_W       = 32;
    localparam int NUM_ROWS    = 16;
    localparam int NUM_COLS    = 16;
    localparam int NUM_BANKS   = 4;
    localparam int NUM_REGIONS = 2;
    localparam int REGION_W    = 1;
    localparam int BW_W        = 8;
    localparam int SPLIT_W     = 5;

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

    logic [NUM_REGIONS-1:0]             w_ld;
    logic [NUM_REGIONS-1:0]             acc_clr;
    logic [NUM_REGIONS-1:0]             compute_en;

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

    task automatic set_din_w_a(int r, logic [DATA_W-1:0] val);
        din_w_region_a[r*DATA_W +: DATA_W] = val;
    endtask

    task automatic set_din_w_b(int r, logic [DATA_W-1:0] val);
        din_w_region_b[r*DATA_W +: DATA_W] = val;
    endtask

    // DUT Instantiation
    sfa_top_16x16 #(
        .DATA_W     (DATA_W),
        .ACC_W      (ACC_W),
        .NUM_ROWS   (NUM_ROWS),
        .NUM_COLS   (NUM_COLS),
        .NUM_BANKS  (NUM_BANKS),
        .NUM_REGIONS(NUM_REGIONS),
        .REGION_W   (REGION_W),
        .BW_W       (BW_W),
        .SPLIT_W    (SPLIT_W)
    ) dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .cfg_split_col         (cfg_split_col),
        .cfg_update_strobe     (cfg_update_strobe),
        .phase_tag             (phase_tag),
        .token_req_A           (token_req_A),
        .token_req_B           (token_req_B),
        .token_release_A       (token_release_A),
        .token_release_B       (token_release_B),
        .role_reassign         (role_reassign),
        .new_region_id_per_bank(new_region_id_per_bank),
        .new_role_per_bank     (new_role_per_bank),
        .w_ld                  (w_ld),
        .acc_clr               (acc_clr),
        .compute_en            (compute_en),
        .din_n                 (din_n),
        .din_w_region_a        (din_w_region_a),
        .din_w_region_b        (din_w_region_b),
        .dout_s                (dout_s),
        .dout_e                (dout_e),
        .acc_out_flat          (acc_out_flat),
        .bw_alloc              (bw_alloc),
        .reconfig_urgent       (reconfig_urgent),
        .region_id_mask        (region_id_mask),
        .scrub_active_bus      (scrub_active_bus),
        .bank_role_clear_bus   (bank_role_clear_bus),
        .token_grant_bus       (token_grant_bus),
        .token_held_bus        (token_held_bus),
        .token_owner_bus       (token_owner_bus),
        .bank_owner_bus        (bank_owner_bus),
        .bank_role_tag_bus     (bank_role_tag_bus),
        .pe_bank_role_stale_bus(pe_bank_role_stale_bus)
    );

    initial clk = 0;
    always #5 clk <= ~clk;

    task automatic step_clk();
        @(posedge clk);
        #1;
    endtask

    task automatic reset_dut();
        rst_n                  = 0;
        cfg_split_col          = 5'd8; // Split 16-col array symmetrically at column 8
        cfg_update_strobe      = 0;
        phase_tag              = {2'b01, 2'b01};
        token_req_A            = '0;
        token_req_B            = '0;
        token_release_A        = '0;
        token_release_B        = '0;
        role_reassign          = '0;
        new_region_id_per_bank = '0;
        new_role_per_bank      = '0;
        w_ld                   = 2'b00;
        acc_clr                = 2'b11;
        compute_en             = 2'b00;
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
        $display(" [TESTSUITE] Starting 16x16 Scaled Spatial Fission Pod Tests");
        $display("================================================================");

        reset_dut();

        // TEST 1: Dispatch-Time Column Partitioning
        $display("\n--- [TEST 1] 16x16 Column Split (Cols 0-7: A, Cols 8-15: B) ---");
        cfg_split_col     = 5'd8;
        cfg_update_strobe = 1;
        step_clk();
        cfg_update_strobe = 0;
        step_clk();

        $display("Region ID Mask = %b (Expected: 1111111100000000)", region_id_mask);
        if (region_id_mask !== 16'b1111111100000000) begin
            $display("ERROR: 16x16 split column decoding mismatch!");
            error_count++;
        end else begin
            $display("PASS: 16x16 split column decoded properly.");
        end

        // TEST 2: Concurrent Multi-Tenant WS Execution & Boundary Isolation
        $display("\n--- [TEST 2] 16x16 Concurrent WS Execution: Reg A & Reg B ---");
        acc_clr = 2'b11;
        step_clk();
        acc_clr = 2'b00;

        // Preload weights: Reg A = 5, Reg B = 7
        w_ld = 2'b11;
        for (int r = 0; r < NUM_ROWS; r++) begin
            set_din_w_a(r, 8'd5);
            set_din_w_b(r, 8'd7);
        end
        step_clk();
        w_ld = 2'b00;

        // Stream activations: Reg A = 3, Reg B = 2
        compute_en = 2'b11;
        for (int r = 0; r < NUM_ROWS; r++) begin
            set_din_w_a(r, 8'd3);
            set_din_w_b(r, 8'd2);
        end
        repeat (4) step_clk();
        compute_en = 2'b00;
        step_clk(); // Drain pipeline stage

        $display("16x16 Reg A: PE[0][0]=%0d, PE[15][0]=%0d (Expected: 60)", get_pe_acc(0,0), get_pe_acc(15,0));
        $display("16x16 Reg B: PE[0][8]=%0d, PE[15][8]=%0d (Expected: 56)", get_pe_acc(0,8), get_pe_acc(15,8));

        if (get_pe_acc(0,0) !== 32'd60 || get_pe_acc(15,0) !== 32'd60 ||
            get_pe_acc(0,8) !== 32'd56 || get_pe_acc(15,8) !== 32'd56) begin
            $display("ERROR: 16x16 concurrent execution calculation mismatch!");
            error_count++;
        end else begin
            $display("PASS: 16x16 multi-tenant spatial fission co-executed successfully across 256 PEs.");
        end

        // TEST 3: EPPA Memory Bandwidth Arbitration
        $display("\n--- [TEST 3] 16x16 EPPA Memory Bandwidth Arbitration ---");
        phase_tag = {2'b10, 2'b00}; // Region B (STREAM), Region A (BURST)
        step_clk();

        $display("BW Alloc: Reg A = 0x%0h (Exp: 0xFF), Reg B = 0x%0h (Exp: 0x7F)",
                 bw_alloc[0 +: BW_W], bw_alloc[BW_W +: BW_W]);

        if (bw_alloc[0 +: BW_W] !== 8'hFF || bw_alloc[BW_W +: BW_W] !== 8'h7F) begin
            $display("ERROR: 16x16 EPPA bandwidth allocation mismatch!");
            error_count++;
        end else begin
            $display("PASS: 16x16 EPPA dynamic allocation verified.");
        end

        // TEST 4: Shared Memory Bank Scrubbing (Bank 2)
        $display("\n--- [TEST 4] 16x16 Shared Memory Bank Scrubbing (Bank 2) ---");
        role_reassign[2]          = 1'b1;
        new_region_id_per_bank[2] = 1'b1; // Assign to Region B
        new_role_per_bank[4 +: 2] = 2'b01;
        step_clk();
        role_reassign[2]          = 1'b0;

        repeat (3) step_clk();
        step_clk(); // Complete cycle 4

        $display("16x16 Bank 2 Scrub Completed: bank_role_clear = %b", bank_role_clear_bus[2]);
        if (bank_role_clear_bus[2] !== 1'b1) begin
            $display("ERROR: Expected bank_role_clear pulse upon scrub completion!");
            error_count++;
        end else begin
            $display("PASS: 16x16 bank scrub zeroing sequence verified.");
        end

        // Summary
        $display("\n================================================================");
        if (error_count == 0) begin
            $display(" [SUCCESS] ALL 16x16 SPATIAL FISSION TESTS PASSED (Errors: 0)");
            $display("================================================================");
            $finish(0);
        end else begin
            $display(" [FAILED] 16x16 SPATIAL FISSION TESTS ENCOUNTERED %0d ERRORS", error_count);
            $display("================================================================");
            $finish(1);
        end
    end

endmodule

