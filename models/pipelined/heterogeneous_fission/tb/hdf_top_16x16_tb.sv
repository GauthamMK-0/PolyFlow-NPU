// hdf_top_16x16_tb.sv — SystemVerilog Testbench for 16x16 Scaled Heterogeneous Fission Pod
// PolyFlow-NPU: 256 Processing Elements verification with Concurrent WS (CNN) and OS (Attention) across 4 Banks.

`timescale 1ns/1ps

module hdf_top_16x16_tb;

    localparam int DATA_W      = 8;
    localparam int ACC_W       = 32;
    localparam int LIFETIME_W  = 8;
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

    logic [2*NUM_REGIONS-1:0]           dataflow_mode;
    logic [NUM_REGIONS-1:0]             lifetime_ld;
    logic [NUM_REGIONS*LIFETIME_W-1:0]  lifetime_init;
    logic [NUM_REGIONS-1:0]             w_ld;
    logic [NUM_REGIONS-1:0]             acc_clr;

    logic [NUM_COLS*ACC_W-1:0]         din_n;
    logic [NUM_ROWS*DATA_W-1:0]         din_w_region_a;
    logic [NUM_ROWS*DATA_W-1:0]         din_w_region_b;

    /* verilator lint_off UNUSEDSIGNAL */
    wire  [NUM_COLS*ACC_W-1:0]         dout_s;
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

    task automatic set_din_n(int c, logic [ACC_W-1:0] val);
        din_n[c*ACC_W +: ACC_W] = val;
    endtask

    task automatic set_din_w_a(int r, logic [DATA_W-1:0] val);
        din_w_region_a[r*DATA_W +: DATA_W] = val;
    endtask

    task automatic set_din_w_b(int r, logic [DATA_W-1:0] val);
        din_w_region_b[r*DATA_W +: DATA_W] = val;
    endtask

    // DUT Instantiation
    hdf_top_16x16 #(
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

    logic signed [ACC_W-1:0] exp_a;
    int k_idx_c;
    int k_idx_r;

    initial begin
        $display("================================================================");
        $display(" [TESTSUITE] Starting 16x16 Scaled Heterogeneous Fission Tests");
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

        // TEST 2: Concurrent Heterogeneous Co-Execution: Reg A (WS) + Reg B (OS)
        $display("\n--- [TEST 2] 16x16 Co-Execution: Reg A (WS) + Reg B (OS) ---");
        din_n          = '0;
        din_w_region_a = '0;
        din_w_region_b = '0;
        repeat (NUM_ROWS + NUM_COLS + 2) step_clk();

        acc_clr       = 2'b11;
        dataflow_mode = {2'b01, 2'b00}; // Reg B: OS (01), Reg A: WS (00)
        lifetime_init = {8'd80, 8'd80};
        lifetime_ld   = 2'b11;
        step_clk();
        acc_clr       = 2'b00;
        lifetime_ld   = 2'b00;

        // Preload weights for Region A (WS) via West-to-East shift (8 cols)
        w_ld[0] = 1'b1;
        for (int step = 7; step >= 0; step--) begin
            for (int r = 0; r < NUM_ROWS; r++) begin
                set_din_w_a(r, 8'd5 + step[7:0]);
            end
            step_clk();
        end
        w_ld[0]        = 1'b0;
        din_w_region_a = '0;

        // Concurrent execution: Region A streams x=3; Region B streams 2 vectors with systolic skew (40)
        for (int t = 0; t < 2 + NUM_ROWS + NUM_COLS + 2; t++) begin
            for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);

            for (int c = 8; c < NUM_COLS; c++) begin
                k_idx_c = t - (c - 8);
                if (k_idx_c == 0)      set_din_n(c, 32'd4);
                else if (k_idx_c == 1) set_din_n(c, 32'd2);
                else                   set_din_n(c, 32'd0);
            end

            for (int r = 0; r < NUM_ROWS; r++) begin
                k_idx_r = t - r;
                if (k_idx_r == 0)      set_din_w_b(r, 8'd7);
                else if (k_idx_r == 1) set_din_w_b(r, 8'd6);
                else                   set_din_w_b(r, 8'd0);
            end

            step_clk();
        end

        din_n          = '0;
        din_w_region_a = '0;
        din_w_region_b = '0;
        step_clk(); // Drain pipeline stage

        $display("16x16 Reg A: PE[0][0]=%0d, PE[15][7]=%0d (Expected: %0d, %0d)",
                 get_pe_acc(0,0), get_pe_acc(15,7), 1*3*(5+0), NUM_ROWS*3*(5+7));
        $display("16x16 Reg B: Verifying all PEs across Region B (Cols 8-15, Expected: 40)");

        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < 8; c++) begin
                exp_a = (r + 1) * 32'd3 * (32'd5 + c);
                if (get_pe_acc(r, c) !== exp_a) begin
                    $display("ERROR: 16x16 Reg A mismatch at PE[%0d][%0d]!", r, c);
                    error_count++;
                end
            end
        end
        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 8; c < NUM_COLS; c++) begin
                if (get_pe_acc(r, c) !== 32'd40) begin
                    $display("ERROR: 16x16 Reg B mismatch at PE[%0d][%0d]: %0d (Expected: 40)!", r, c, get_pe_acc(r, c));
                    error_count++;
                end
            end
        end
        if (error_count == 0) begin
            $display("PASS: 16x16 Reg A (WS) and Reg B (OS) executed concurrently across all 256 PEs!");
        end

        // TEST 3: EPPA Bandwidth Arbitration
        $display("\n--- [TEST 3] 16x16 EPPA Dynamic Bandwidth Arbitration ---");
        phase_tag = {2'b10, 2'b00}; // Reg B (STREAM), Reg A (BURST)
        step_clk();

        $display("BW Alloc: Reg A = 0x%0h (Exp: 0xFF), Reg B = 0x%0h (Exp: 0x7F)",
                 bw_alloc[0 +: BW_W], bw_alloc[BW_W +: BW_W]);

        if (bw_alloc[0 +: BW_W] !== 8'hFF || bw_alloc[BW_W +: BW_W] !== 8'h7F) begin
            $display("ERROR: 16x16 EPPA bandwidth allocation mismatch!");
            error_count++;
        end else begin
            $display("PASS: 16x16 EPPA dynamic allocation verified.");
        end

        // TEST 4: Shared Memory Migration (Bank 2 -> Region B)
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
            $display("PASS: 16x16 memory bank scrub zeroing sequence verified.");
        end

        // Summary
        $display("\n================================================================");
        if (error_count == 0) begin
            $display(" [SUCCESS] ALL 16x16 HETEROGENEOUS FISSION TESTS PASSED (Errors: 0)");
            $display("================================================================");
            $finish(0);
        end else begin
            $display(" [FAILED] 16x16 HETEROGENEOUS FISSION TESTS ENCOUNTERED %0d ERRORS", error_count);
            $display("================================================================");
            $finish(1);
        end
    end

endmodule

