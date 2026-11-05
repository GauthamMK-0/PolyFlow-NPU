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

    logic [NUM_COLS*ACC_W-1:0]         din_n;
    logic [NUM_ROWS*DATA_W-1:0]         din_w_region_a;
    logic [NUM_ROWS*DATA_W-1:0]         din_w_region_b;

    /* verilator lint_off UNUSEDSIGNAL */
    wire  [NUM_COLS*ACC_W-1:0]         dout_s;
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

    // Output capture buffers for Region A and Region B
    logic signed [ACC_W-1:0] hw_cnn_out [0:K_STEPS-1][0:HALF_COLS-1];
    logic signed [ACC_W-1:0] hw_vit_out [0:NUM_ROWS-1][0:HALF_COLS-1];
    int m_idx;
    int tile_k_start;
    localparam int NUM_TILES = K_STEPS / NUM_ROWS;
    localparam int TILE_COMP_LEN  = NUM_ROWS + NUM_ROWS + HALF_COLS + 2;
    localparam int TILE_TOTAL_LEN = HALF_COLS + TILE_COMP_LEN;
    localparam int TOTAL_CYCLES_A = HALF_COLS + K_STEPS + NUM_ROWS + HALF_COLS + 2;
    localparam int TOTAL_CYCLES_B = NUM_TILES * TILE_TOTAL_LEN;
    localparam int MAX_SIM_CYCLES = (TOTAL_CYCLES_A > TOTAL_CYCLES_B) ? TOTAL_CYCLES_A : TOTAL_CYCLES_B;

    int cur_tile;
    int sub_cycle;
    int step_col;
    int t_c;
    int t_a;

    int cycle_count = 0;
    int start_cycle_total = 0;
    int end_cycle_reg_a = 0;
    int end_cycle_reg_b = 0;
    int total_active_macs = 0;

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

        // Initialize output capture buffers
        for (int m = 0; m < K_STEPS; m++) begin
            for (int c = 0; c < HALF_COLS; c++) begin
                hw_cnn_out[m][c] = '0;
            end
        end
        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < HALF_COLS; c++) begin
                hw_vit_out[r][c] = '0;
            end
        end

        // Concurrent execution:
        // Region A: Native WS Conv2D across ALL K_STEPS activation vectors (1 weight preload + streaming)
        // Region B: ViT Attention in Forced WS mode (NUM_TILES reload & compute cycles)
        for (int cycle = 0; cycle < MAX_SIM_CYCLES; cycle++) begin
            // --- Region A ---
            if (cycle < TOTAL_CYCLES_A) begin
                if (cycle < HALF_COLS) begin
                    w_ld[0]       = 1'b1;
                    compute_en[0] = 1'b0;
                    for (int r = 0; r < NUM_ROWS; r++) begin
                        set_din_w_a(r, cnn_weights_mem[r][HALF_COLS - 1 - cycle]);
                    end
                    for (int c = 0; c < HALF_COLS; c++) begin
                        set_din_n(c, 32'd0);
                    end
                end else begin
                    w_ld[0]       = 1'b0;
                    compute_en[0] = 1'b1;
                    t_a = cycle - HALF_COLS;
                    for (int r = 0; r < NUM_ROWS; r++) begin
                        m_idx = t_a - r;
                        if (m_idx >= 0 && m_idx < K_STEPS) begin
                            set_din_w_a(r, cnn_inputs_mem[m_idx][r]);
                        end else begin
                            set_din_w_a(r, 8'd0);
                        end
                    end
                    for (int c = 0; c < HALF_COLS; c++) begin
                        set_din_n(c, 32'd0);
                        m_idx = t_a - (NUM_ROWS + 1 + c);
                        if (m_idx >= 0 && m_idx < K_STEPS) begin
                            hw_cnn_out[m_idx][c] = $signed(dout_s[c*ACC_W +: ACC_W]);
                        end
                    end
                    if (t_a < K_STEPS) total_active_macs += (NUM_ROWS * HALF_COLS);
                end
            end else begin
                w_ld[0]        = 1'b0;
                compute_en[0]  = 1'b0;
                din_w_region_a = '0;
            end

            // --- Region B ---
            if (cycle < TOTAL_CYCLES_B) begin
                cur_tile     = cycle / TILE_TOTAL_LEN;
                sub_cycle    = cycle % TILE_TOTAL_LEN;
                tile_k_start = cur_tile * NUM_ROWS;

                if (sub_cycle < HALF_COLS) begin
                    // Preload / Reload weights for current tile
                    w_ld[1]       = 1'b1;
                    compute_en[1] = 1'b0;
                    step_col      = HALF_COLS - 1 - sub_cycle;
                    for (int r = 0; r < NUM_ROWS; r++) begin
                        set_din_w_b(r, vit_q_mem[tile_k_start + r][HALF_COLS + step_col]);
                    end
                end else begin
                    // Systolic compute for current tile
                    w_ld[1]       = 1'b0;
                    compute_en[1] = 1'b1;
                    t_c           = sub_cycle - HALF_COLS;
                    for (int r = 0; r < NUM_ROWS; r++) begin
                        m_idx = t_c - r;
                        if (m_idx >= 0 && m_idx < NUM_ROWS) begin
                            set_din_w_b(r, vit_k_mem[tile_k_start + r][m_idx]);
                        end else begin
                            set_din_w_b(r, 8'd0);
                        end
                    end
                    for (int c = HALF_COLS; c < NUM_COLS; c++) begin
                        set_din_n(c, 32'd0);
                        m_idx = t_c - (NUM_ROWS + 1 + (c - HALF_COLS));
                        if (m_idx >= 0 && m_idx < NUM_ROWS) begin
                            hw_vit_out[m_idx][c - HALF_COLS] += $signed(dout_s[c*ACC_W +: ACC_W]);
                        end
                    end
                    if (t_c < NUM_ROWS) total_active_macs += (NUM_ROWS * HALF_COLS);
                end
            end else begin
                w_ld[1]        = 1'b0;
                compute_en[1]  = 1'b0;
                din_w_region_b = '0;
            end

            step_clk();
            if (cycle == TOTAL_CYCLES_A) begin
                end_cycle_reg_a = cycle_count;
            end
        end

        // Drain final registers
        din_n          = '0;
        din_w_region_a = '0;
        din_w_region_b = '0;
        w_ld           = 2'b00;
        compute_en     = 2'b00;
        step_clk();
        end_cycle_reg_b = cycle_count;

        $display("Region A (CNN Native WS) Completed: %0d cycles", (end_cycle_reg_a - start_cycle_total));
        $display("Region B (ViT Forced WS) Completed: %0d cycles (Stretched by per-tile WS reload)", (end_cycle_reg_b - start_cycle_total));

        // Dump Region A output (K_STEPS x HALF_COLS)
        fp = $fopen({"benchmarks/results/", `SCALE_NAME, "/m2_reg_a_hw_output.txt"}, "w");
        for (int m = 0; m < K_STEPS; m++) begin
            for (int c = 0; c < HALF_COLS; c++) begin
                $fwrite(fp, "%0d ", hw_cnn_out[m][c]);
            end
            $fwrite(fp, "\n");
        end
        $fclose(fp);

        // Dump Region B output (NUM_ROWS x HALF_COLS)
        fp = $fopen({"benchmarks/results/", `SCALE_NAME, "/m2_reg_b_hw_output.txt"}, "w");
        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < HALF_COLS; c++) begin
                $fwrite(fp, "%0d ", hw_vit_out[r][c]);
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
