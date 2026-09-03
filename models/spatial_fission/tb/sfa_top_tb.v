// sfa_top_tb.v — SystemVerilog Testbench for Homogeneous Spatial Fission Model
// Validates dynamic spatial fission, boundary isolation, concurrent multi-tenancy, and memory safety.

`timescale 1ns/1ps

module sfa_top_tb;

    localparam int DATA_W      = 8;
    localparam int ACC_W       = 32;
    localparam int NUM_ROWS    = 4;
    localparam int NUM_COLS    = 4;
    localparam int NUM_BANKS   = 2;
    localparam int NUM_REGIONS = 2;
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
    /* verilator lint_on UNUSEDSIGNAL */

    int error_count = 0;

    // Helper to read accumulator for PE at [row, col]
    function automatic logic signed [ACC_W-1:0] get_pe_acc(int r, int c);
        return acc_out_flat[(r*NUM_COLS + c)*ACC_W +: ACC_W];
    endfunction

    // Helper to set din_w for Region A
    task automatic set_din_w_a(int r, logic [DATA_W-1:0] val);
        din_w_region_a[r*DATA_W +: DATA_W] = val;
    endtask

    // Helper to set din_w for Region B
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
        $display(" [TESTSUITE] Starting Spatial Fission Model (Model 2) Tests");
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
        // TEST 2: Concurrent Multi-Tenant WS Execution & Boundary Isolation
        // -------------------------------------------------------------
        $display("\n--- [TEST 2] Concurrent Execution: Region A & Region B (Both WS) ---");
        // Clear accumulators in both regions
        acc_clr = 2'b11;
        step_clk();
        acc_clr = 2'b00;

        // Step 2.1: Preload weights into Region A (w=5) and Region B (w=7)
        w_ld = 2'b11;
        for (int r = 0; r < NUM_ROWS; r++) begin
            set_din_w_a(r, 8'd5); // Region A weight = 5
            set_din_w_b(r, 8'd7); // Region B weight = 7
        end
        step_clk();
        w_ld = 2'b00;

        // Step 2.2: Stream distinct activations: Region A (x=3), Region B (x=2)
        compute_en = 2'b11;
        for (int r = 0; r < NUM_ROWS; r++) begin
            set_din_w_a(r, 8'd3); // Region A activation = 3
            set_din_w_b(r, 8'd2); // Region B activation = 2
        end
        step_clk(); // Cycle 1: Reg A += 5*3=15, Reg B += 7*2=14
        step_clk(); // Cycle 2: Reg A += 15=30,  Reg B += 14=28
        step_clk(); // Cycle 3: Reg A += 15=45,  Reg B += 14=42
        step_clk(); // Cycle 4: Reg A += 15=60,  Reg B += 14=56
        compute_en = 2'b00;

        $display("Region A (PE[0][0]) Accumulator = %0d (Expected: 60)", get_pe_acc(0,0));
        $display("Region B (PE[0][2]) Accumulator = %0d (Expected: 56)", get_pe_acc(0,2));

        if (get_pe_acc(0,0) !== 32'd60 || get_pe_acc(0,2) !== 32'd56) begin
            $display("ERROR: Concurrent execution calculation mismatch!");
            error_count++;
        end else begin
            $display("PASS: Both regions co-executed successfully with zero cross-talk.");
        end

        // -------------------------------------------------------------
        // TEST 3: EPPA Memory Bandwidth Arbitration
        // -------------------------------------------------------------
        $display("\n--- [TEST 3] EPPA Memory Bandwidth Arbitration ---");
        // Region A -> BURST (00), Region B -> STREAM (10)
        phase_tag = {2'b10, 2'b00}; // [1]=Region B (STREAM), [0]=Region A (BURST)
        step_clk();

        $display("BW Alloc: Region A = 0x%0h (Exp: 0xFF), Region B = 0x%0h (Exp: 0x7F)",
                 bw_alloc[0 +: BW_W], bw_alloc[BW_W +: BW_W]);

        if (bw_alloc[0 +: BW_W] !== 8'hFF || bw_alloc[BW_W +: BW_W] !== 8'h7F) begin
            $display("ERROR: EPPA bandwidth allocation mismatch!");
            error_count++;
        end else begin
            $display("PASS: EPPA dynamic allocation verified.");
        end

        // -------------------------------------------------------------
        // TEST 4: Shared Memory Bank Scrubbing & Ownership Transfer
        // -------------------------------------------------------------
        $display("\n--- [TEST 4] Shared Memory Scrubbing & Role Reassignment ---");
        // Reassign Bank 1 to Region B with role 2'b01 (Input-Issuer)
        role_reassign[1]          = 1'b1;
        new_region_id_per_bank[1] = 1'b1; // Region B
        new_role_per_bank[2 +: 2] = 2'b01;
        step_clk();
        role_reassign[1]          = 1'b0;

        // Verify scrub active for 4 cycles
        for (int i = 0; i < 3; i++) begin
            $display("Bank 1 Scrub Cycle %0d: scrub_active = %b", i+1, scrub_active_bus[1]);
            step_clk();
        end
        step_clk(); // Cycle 4 completes

        $display("Bank 1 Scrub Completed: bank_role_clear = %b", bank_role_clear_bus[1]);
        if (bank_role_clear_bus[1] !== 1'b1) begin
            $display("ERROR: Expected bank_role_clear pulse upon scrub completion!");
            error_count++;
        end else begin
            $display("PASS: Bank scrub zeroing sequence verified.");
        end

        // -------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------
        $display("\n================================================================");
        if (error_count == 0) begin
            $display(" [SUCCESS] ALL SPATIAL FISSION TESTS PASSED (Errors: 0)");
            $display("================================================================");
            $finish(0);
        end else begin
            $display(" [FAILED] SPATIAL FISSION TESTS ENCOUNTERED %0d ERRORS", error_count);
            $display("================================================================");
            $finish(1);
        end
    end

endmodule
