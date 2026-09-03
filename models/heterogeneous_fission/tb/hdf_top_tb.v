// hdf_top_tb.v — SystemVerilog Testbench for Novel Heterogeneous Fission Model (DRDS-NPU / HDF-NPU)
// Verifies concurrent multi-tenant execution of CNN (Weight-Stationary) and Transformer Attention (Output-Stationary).

`timescale 1ns/1ps

module hdf_top_tb;

    localparam int DATA_W      = 8;
    localparam int ACC_W       = 32;
    localparam int LIFETIME_W  = 4;
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
    /* verilator lint_on UNUSEDSIGNAL */

    wire  [NUM_ROWS*NUM_COLS*ACC_W-1:0] acc_out_flat;
    wire  [NUM_REGIONS*BW_W-1:0]        bw_alloc;
    wire  [NUM_COLS-1:0]                region_id_mask;

    int error_count = 0;

    // Helper to read accumulator for PE at [row, col]
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
    hdf_top #(
        .DATA_W     (DATA_W),
        .ACC_W      (ACC_W),
        .LIFETIME_W (LIFETIME_W),
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
        .dataflow_mode         (dataflow_mode),
        .lifetime_ld           (lifetime_ld),
        .lifetime_init         (lifetime_init),
        .w_ld                  (w_ld),
        .acc_clr               (acc_clr),
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
        .bank_role_clear_bus   (bank_role_clear_bus)
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
        dataflow_mode          = {2'b01, 2'b00}; // Reg B: OS (01), Reg A: WS (00)
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
        $display(" [TESTSUITE] Starting Heterogeneous Fission Model (Model 3) Tests");
        $display("================================================================");

        reset_dut();

        // -------------------------------------------------------------
        // TEST 1: Dispatch-Time Column Partitioning
        // -------------------------------------------------------------
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

        // -------------------------------------------------------------
        // TEST 2: Heterogeneous Co-Execution: Region A (WS) + Region B (OS)
        // -------------------------------------------------------------
        $display("\n--- [TEST 2] Heterogeneous Co-Execution: Region A (WS) + Region B (OS) ---");
        // Clear accumulators in both regions
        acc_clr = 2'b11;
        dataflow_mode = {2'b01, 2'b00}; // Reg B: OS (01), Reg A: WS (00)
        step_clk();
        acc_clr = 2'b00;

        // Step 2.1: Preload weights for Region A (WS) & initialize lifetime counter for both
        w_ld[0]          = 1'b1;
        lifetime_ld      = 2'b11;
        lifetime_init    = {4'd15, 4'd15}; // 15 cycles lifetime for both regions
        for (int r = 0; r < NUM_ROWS; r++) begin
            set_din_w_a(r, 8'd5); // Region A stationary weight = 5
        end
        step_clk();
        w_ld[0]     = 1'b0;
        lifetime_ld = 2'b00;

        // Step 2.2: Concurrent execution:
        // Region A receives streaming activations from West: x_A = 3
        // Region B receives Q from North and K from West simultaneously:
        // Cycle 1: Q=4, K=7 -> Region B prod = 28; Region A prod = 5*3 = 15
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
        for (int c = 2; c < NUM_COLS; c++) set_din_n(c, 8'd4);  // Q into Region B cols 2-3
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_b(r, 8'd7); // K into Region B rows
        step_clk();

        // Cycle 2: Q=2, K=6 -> Region B prod = 12 (acc = 28+12=40); Region A prod = 15 (acc = 15+15=30)
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
        for (int c = 2; c < NUM_COLS; c++) set_din_n(c, 8'd2);
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_b(r, 8'd6);
        step_clk();

        // Cycle 3: Region A continues compute (x_A=3) -> acc = 30+15 = 45
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
        for (int c = 2; c < NUM_COLS; c++) set_din_n(c, 8'd0);
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_b(r, 8'd0);
        step_clk();

        // Cycle 4: Region A continues compute (x_A=3) -> acc = 45+15 = 60
        for (int r = 0; r < NUM_ROWS; r++) set_din_w_a(r, 8'd3);
        step_clk();

        $display("Region A (WS Mode, PE[0][0]) Accumulator = %0d (Expected: 60)", get_pe_acc(0,0));
        $display("Region B (OS Mode, PE[0][2]) Accumulator = %0d (Expected: 40)", get_pe_acc(0,2));

        if (get_pe_acc(0,0) !== 32'd60 || get_pe_acc(0,2) !== 32'd40) begin
            $display("ERROR: Heterogeneous co-execution calculation mismatch!");
            error_count++;
        end else begin
            $display("PASS: Region A (WS) and Region B (OS) executed simultaneously with correct mathematics!");
        end

        // -------------------------------------------------------------
        // TEST 3: Dynamic EPPA Phase Arbitration under Heterogeneous Loads
        // -------------------------------------------------------------
        $display("\n--- [TEST 3] EPPA Bandwidth Arbitration (WS BURST + OS STREAM) ---");
        // Region A is in BURST (00), Region B is in STREAM (10)
        phase_tag = {2'b10, 2'b00};
        step_clk();

        $display("BW Alloc: Region A (BURST) = 0x%0h (Exp: 0xFF), Region B (STREAM) = 0x%0h (Exp: 0x7F)",
                 bw_alloc[0 +: BW_W], bw_alloc[BW_W +: BW_W]);

        if (bw_alloc[0 +: BW_W] !== 8'hFF || bw_alloc[BW_W +: BW_W] !== 8'h7F) begin
            $display("ERROR: EPPA bandwidth allocation mismatch!");
            error_count++;
        end else begin
            $display("PASS: EPPA dynamic allocation correctly reflects heterogeneous memory phase profiles.");
        end

        // -------------------------------------------------------------
        // TEST 4: Shared Memory Ownership Migration with Mandatory Scrubbing
        // -------------------------------------------------------------
        $display("\n--- [TEST 4] Shared Memory Migration (Bank 0 -> Region B) ---");
        // Reassign Bank 0 to Region B with role Input-Issuer (2'b01)
        role_reassign[0]          = 1'b1;
        new_region_id_per_bank[0] = 1'b1;
        new_role_per_bank[0 +: 2] = 2'b01;
        step_clk();
        role_reassign[0]          = 1'b0;

        for (int i = 0; i < 3; i++) begin
            $display("Bank 0 Scrub Cycle %0d: scrub_active = %b", i+1, scrub_active_bus[0]);
            step_clk();
        end
        step_clk(); // 4th cycle completes scrub

        $display("Bank 0 Scrub Completed: bank_role_clear = %b", bank_role_clear_bus[0]);
        if (bank_role_clear_bus[0] !== 1'b1) begin
            $display("ERROR: Expected bank_role_clear pulse!");
            error_count++;
        end else begin
            $display("PASS: Memory bank migration and scrubbing safety verified.");
        end

        // -------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------
        $display("\n================================================================");
        if (error_count == 0) begin
            $display(" [SUCCESS] ALL HETEROGENEOUS FISSION TESTS PASSED (Errors: 0)");
            $display("================================================================");
            $finish(0);
        end else begin
            $display(" [FAILED] HETEROGENEOUS FISSION TESTS ENCOUNTERED %0d ERRORS", error_count);
            $display("================================================================");
            $finish(1);
        end
    end

endmodule
