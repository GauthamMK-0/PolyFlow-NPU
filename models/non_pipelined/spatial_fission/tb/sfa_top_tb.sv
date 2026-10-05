// sfa_top_tb.sv — SystemVerilog Hybrid Harness for Non-Pipelined Spatial Fission Model
// Modular test dispatcher compatible with both Verilator and Cadence Xcelium.

`timescale 1ns/1ps

module sfa_top_tb;

    localparam int DATA_W      = 8;
    localparam int ACC_W       = 32;
    localparam int NUM_ROWS    = 4;
    localparam int NUM_COLS    = 4;
    localparam int NUM_BANKS   = 2;
    localparam int NUM_REGIONS = 2;
    localparam int REGION_W    = 1;
    localparam int BW_W        = 8;

    logic clk;
    logic rst_n;

    logic [3:0]                         cfg_split_col;
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
    /* verilator lint_on UNUSEDSIGNAL */
    wire  [NUM_ROWS*NUM_COLS*ACC_W-1:0] acc_out_flat;
    wire  [NUM_REGIONS*BW_W-1:0]        bw_alloc;
    wire  [NUM_COLS-1:0]                region_id_mask;
    /* verilator lint_off UNUSEDSIGNAL */
    wire  [NUM_BANKS-1:0]               scrub_active_bus;
    wire  [NUM_BANKS-1:0]               bank_role_clear_bus;
    wire  [NUM_BANKS*NUM_REGIONS-1:0]   token_grant_bus;
    wire  [NUM_BANKS-1:0]               token_held_bus;
    wire  [NUM_BANKS*REGION_W-1:0]      token_owner_bus;
    wire  [NUM_BANKS*REGION_W-1:0]      bank_owner_bus;
    wire  [NUM_BANKS*2-1:0]             bank_role_tag_bus;
    wire  [NUM_COLS-1:0]                pe_bank_role_stale_bus;
    /* verilator lint_on UNUSEDSIGNAL */

    int error_count = 0;
    string target_test = "ALL";

    // Helper to read accumulator for PE at [row, col]
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
    sfa_top #(
        .DATA_W     (DATA_W),
        .ACC_W      (ACC_W),
        .NUM_ROWS   (NUM_ROWS),
        .NUM_COLS   (NUM_COLS),
        .NUM_BANKS  (NUM_BANKS),
        .NUM_REGIONS(NUM_REGIONS),
        .REGION_W   (REGION_W),
        .BW_W       (BW_W)
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
        cfg_split_col          = 4'd2; // Split 4-col array at column 2 (Cols 0-1: Reg A, Cols 2-3: Reg B)
        cfg_update_strobe      = 0;
        phase_tag              = {2'b01, 2'b01}; // Both regions IDLE
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

    // --- Modular Test Inclusions (Hybrid Harness Pattern) ---
    `include "tests/test_split_partition.svh"
    `include "tests/test_concurrent_ws.svh"
    `include "tests/test_eppa_phase_arb.svh"
    `include "tests/test_mem_scrub.svh"

    // --- Test Dispatcher & Regression Summary ---
    initial begin
        void'($value$plusargs("TEST=%s", target_test));

        $display("================================================================");
        $display(" [HYBRID HARNESS] Spatial Fission Model (Non-Pipelined)");
        $display(" Target Test Selection: %s", target_test);
        $display("================================================================");

        if (target_test == "ALL" || target_test == "split") begin
            reset_dut();
            run_test_split_partition();
        end

        if (target_test == "ALL" || target_test == "concurrent") begin
            reset_dut();
            run_test_concurrent_ws();
        end

        if (target_test == "ALL" || target_test == "eppa") begin
            reset_dut();
            run_test_eppa_phase_arb();
        end

        if (target_test == "ALL" || target_test == "scrub") begin
            reset_dut();
            run_test_mem_scrub();
        end

        $display("\n================================================================");
        if (error_count == 0) begin
            $display(" [SUCCESS] ALL EXECUTED SPATIAL FISSION TESTS PASSED (Errors: 0)");
            $display("================================================================");
            $finish(0);
        end else begin
            $display(" [FAILED] SPATIAL FISSION TESTS ENCOUNTERED %0d ERRORS", error_count);
            $display("================================================================");
            $finish(1);
        end
    end

endmodule
