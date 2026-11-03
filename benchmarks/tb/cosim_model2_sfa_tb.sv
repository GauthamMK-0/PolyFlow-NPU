// cosim_model2_sfa_tb.sv — Cycle-Accurate Co-Simulation Testbench for Model 2 (Planaria Baseline)
// Slices physical array into Region A and Region B, with BOTH regions hardware-pinned to Weight-Stationary (WS).
// Region A executes CNN natively (1 weight load + K compute cycles).
// Region B executes ViT Attention Q*K^T in forced WS mode: since K[k][r] changes on every step k,
// sfa_pe must alternate 1 cycle of w_ld (loading K[k][r] into stat_weight) and 1 cycle of compute_en (multiplying by Q[k]),
// producing the 100% bit-exact mathematical output while exposing the true physical WS reload stall penalty.

`timescale 1ns/1ps

`ifndef NUM_ROWS
`define NUM_ROWS 4
`endif
`ifndef NUM_COLS
`define NUM_COLS 4
`endif
`ifndef K_STEPS
`define K_STEPS 16
`endif
`ifndef SCALE_NAME
`define SCALE_NAME "4x4"
`endif

module cosim_model2_sfa_tb;

    localparam int DATA_W      = 8;
    localparam int ACC_W       = 32;
    localparam int NUM_ROWS    = `NUM_ROWS;
    localparam int NUM_COLS    = `NUM_COLS;
    localparam int K_STEPS     = `K_STEPS;
    localparam int NUM_BANKS   = (NUM_COLS >= 16) ? 4 : 2;
    localparam int NUM_REGIONS = 2;
    localparam int REGION_W    = 1;
    localparam int BW_W        = 8;
    localparam int SPLIT_W     = ($clog2(NUM_COLS + 1) >= 4) ? $clog2(NUM_COLS + 1) : 4;
    localparam int HALF_COLS   = NUM_COLS / 2;

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
    wire  [NUM_REGIONS*BW_W-1:0]        bw_alloc;
    wire  [NUM_REGIONS-1:0]             reconfig_urgent;
    wire  [NUM_COLS-1:0]                region_id_mask;
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

    // Workload memory buffers
    logic [DATA_W-1:0] cnn_weights_mem [0:NUM_ROWS-1][0:NUM_COLS-1];
    logic [DATA_W-1:0] cnn_inputs_mem  [0:K_STEPS-1][0:NUM_ROWS-1];
    logic [DATA_W-1:0] vit_q_mem       [0:K_STEPS-1][0:NUM_COLS-1];
    logic [DATA_W-1:0] vit_k_mem       [0:K_STEPS-1][0:NUM_ROWS-1];

    int cycle_count = 0;
    int start_cycle_total = 0;
    int end_cycle_reg_a = 0;
    int end_cycle_reg_b = 0;
    int total_active_macs = 0;

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

    always @(posedge clk) begin
        if (rst_n) cycle_count++;
    end

    task automatic step_clk();
        @(posedge clk);
        #1;
    endtask

    integer fp;

    initial begin
        $display("================================================================");
        $display(" [BENCHMARK] Model 2: Homogeneous Spatial Fission (Planaria) [%0dx%0d]", NUM_ROWS, NUM_COLS);
        $display(" Workload: Multi-Tenant Split (50/50) -> Region A (WS) & Region B (FORCED WS)");
        $display("================================================================");

        $readmemh({"benchmarks/data/", `SCALE_NAME, "/cnn_weights.mem"}, cnn_weights_mem);
        $readmemh({"benchmarks/data/", `SCALE_NAME, "/cnn_inputs.mem"},  cnn_inputs_mem);
        $readmemh({"benchmarks/data/", `SCALE_NAME, "/vit_q.mem"},       vit_q_mem);
        $readmemh({"benchmarks/data/", `SCALE_NAME, "/vit_k.mem"},       vit_k_mem);

        // Reset & Partition Configuration
        rst_n                  = 0;
        cfg_split_col          = HALF_COLS[SPLIT_W-1:0];
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
        #1;
        cycle_count = 0;

        // -------------------------------------------------------------
        // Concurrent Multi-Tenant Execution
        // Region A: CNN (Native WS mode: 1 w_ld + K compute + 1 drain)
        // Region B: ViT Attention (Forced WS mode on sfa_pe: K pairs of [w_ld K[k], compute Q[k]] + 1 drain)
        // -------------------------------------------------------------
        start_cycle_total = cycle_count;

        // Cycle 1: Strobe column split boundary & clear accumulators
        cfg_update_strobe = 1;
        acc_clr           = 2'b11;
        step_clk();
        cfg_update_strobe = 0;
        acc_clr           = 2'b00;

        $display("Dynamic Boundary Split applied at Col %0d (Mask = %b)", HALF_COLS, region_id_mask);

        // Cycles 2 .. 2K+1: Execute Region A (finishes at t = K+1) and Region B (finishes at t = 2K) concurrently
        for (int t = 0; t < 2 * K_STEPS; t++) begin
            // --- Region A (CNN in Native WS) ---
            if (t == 0) begin
                // Preload stationary CNN weights
                w_ld[0]       = 1'b1;
                compute_en[0] = 1'b0;
                for (int r = 0; r < NUM_ROWS; r++) begin
                    set_din_w_a(r, cnn_weights_mem[r][0]);
                end
            end else if (t >= 1 && t <= K_STEPS) begin
                // Stream K_STEPS CNN activations
                w_ld[0]       = 1'b0;
                compute_en[0] = 1'b1;
                for (int r = 0; r < NUM_ROWS; r++) begin
                    set_din_w_a(r, cnn_inputs_mem[t-1][r]);
                end
                total_active_macs += (NUM_ROWS * HALF_COLS);
            end else begin
                // Region A drain & idle while waiting for Region B
                w_ld[0]        = 1'b0;
                compute_en[0]  = 1'b0;
                din_w_region_a = '0;
            end

            // --- Region B (ViT Attention Forced into WS on sfa_pe) ---
            if ((t % 2) == 0) begin
                // Even step (t = 2k): Must reload non-stationary key vector K[k][r] into stat_weight
                w_ld[1]       = 1'b1;
                compute_en[1] = 1'b0;
                for (int r = 0; r < NUM_ROWS; r++) begin
                    set_din_w_b(r, vit_k_mem[t/2][r]);
                end
            end else begin
                // Odd step (t = 2k+1): Multiply stat_weight (K[k][r]) by Q[k]
                w_ld[1]       = 1'b0;
                compute_en[1] = 1'b1;
                for (int r = 0; r < NUM_ROWS; r++) begin
                    set_din_w_b(r, vit_q_mem[t/2][0]);
                end
                total_active_macs += (NUM_ROWS * HALF_COLS);
            end

            step_clk();

            // Record exact cycle when Region A finishes its 1-cycle pipeline drain (at end of t == K_STEPS + 1)
            if (t == K_STEPS + 1) begin
                end_cycle_reg_a = cycle_count;
                $display("Region A (CNN Native WS) Completed: %0d cycles", (end_cycle_reg_a - start_cycle_total));
            end
        end

        // Final 1-cycle pipeline drain for Region B's last product (t = 2K-1)
        w_ld           = 2'b00;
        compute_en     = 2'b00;
        din_w_region_a = '0;
        din_w_region_b = '0;
        step_clk();

        end_cycle_reg_b = cycle_count;
        $display("Region B (ViT Forced WS) Completed: %0d cycles (Stretched by per-step WS reload)", (end_cycle_reg_b - start_cycle_total));

        // Dump hardware output
        fp = $fopen({"benchmarks/results/", `SCALE_NAME, "/m2_multitenant_hw_output.txt"}, "w");
        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < NUM_COLS; c++) begin
                $fwrite(fp, "%0d ", get_pe_acc(r, c));
            end
            $fwrite(fp, "\n");
        end
        $fclose(fp);

        // Dump metrics JSON
        fp = $fopen({"benchmarks/results/", `SCALE_NAME, "/m2_metrics.json"}, "w");
        $fwrite(fp, "{\n");
        $fwrite(fp, "  \"model\": \"Model 2 (Homogeneous Spatial Fission)\",\n");
        $fwrite(fp, "  \"scale\": \"%s\",\n", `SCALE_NAME);
        $fwrite(fp, "  \"reg_a_cycles\": %0d,\n", (end_cycle_reg_a - start_cycle_total));
        $fwrite(fp, "  \"reg_b_cycles\": %0d,\n", (end_cycle_reg_b - start_cycle_total));
        $fwrite(fp, "  \"total_makespan_cycles\": %0d,\n", (end_cycle_reg_b - start_cycle_total));
        $fwrite(fp, "  \"total_valid_macs\": %0d\n", total_active_macs);
        $fwrite(fp, "}\n");
        $fclose(fp);

        $display("\n================================================================");
        $display(" [SUMMARY: MODEL 2 HOMOGENEOUS FISSION]");
        $display("   Region A (CNN Native WS) Cycles: %0d", (end_cycle_reg_a - start_cycle_total));
        $display("   Region B (ViT Forced WS) Cycles: %0d", (end_cycle_reg_b - start_cycle_total));
        $display("   Total Co-Run Makespan Cycles:    %0d", (end_cycle_reg_b - start_cycle_total));
        $display("   Total Useful MACs:               %0d", total_active_macs);
        $display("================================================================");
        $finish;
    end

endmodule
