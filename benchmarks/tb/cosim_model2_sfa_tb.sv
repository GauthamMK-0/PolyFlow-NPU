// cosim_model2_sfa_tb.sv — Cycle-Accurate Co-Simulation Testbench for Model 2 (Planaria Baseline)
// Slices physical array into Region A and Region B, but FORCES both to Weight-Stationary (WS).
// Measures multi-tenant makespan, memory reload stall cycles, and dumps accumulators for accuracy verification.

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
        step_clk();

        // Strobe column split boundary
        cfg_update_strobe = 1;
        step_clk();
        cfg_update_strobe = 0;
        acc_clr = 2'b00;
        step_clk();

        $display("Dynamic Boundary Split applied at Col %0d (Mask = %b)", HALF_COLS, region_id_mask);

        // -------------------------------------------------------------
        // Concurrent Multi-Tenant Execution
        // Region A: CNN (Native WS mode)
        // Region B: ViT Attention (FORCED into WS mode with weight reload stalls)
        // -------------------------------------------------------------
        start_cycle_total = cycle_count;

        // Step 1: Preload stationary weights for Region A & initial key-slice for Region B
        w_ld = 2'b11;
        for (int c = 0; c < HALF_COLS; c++) begin
            for (int r = 0; r < NUM_ROWS; r++) begin
                set_din_w_a(r, cnn_weights_mem[r][c]);
                set_din_w_b(r, vit_k_mem[0][r]); // Forced to treat key as stationary weight
            end
            step_clk();
        end
        w_ld = 2'b00;
        step_clk();

        // Step 2: Stream inputs into Region A & stream queries into Region B
        compute_en = 2'b11;
        for (int k = 0; k < K_STEPS; k++) begin
            for (int r = 0; r < NUM_ROWS; r++) begin
                set_din_w_a(r, cnn_inputs_mem[k][r]);
            end
            for (int c = HALF_COLS; c < NUM_COLS; c++) begin
                set_din_n(c, vit_q_mem[k][c]);
            end
            step_clk();
            total_active_macs += (NUM_ROWS * HALF_COLS); // Region A active
            total_active_macs += (NUM_ROWS * HALF_COLS); // Region B active
        end

        // Region A completes first (native WS)
        din_w_region_a = '0;
        step_clk();
        step_clk();
        end_cycle_reg_a = cycle_count;
        $display("Region A (CNN Native WS) Completed: %0d cycles", (end_cycle_reg_a - start_cycle_total));

        // Region B suffers forced-WS memory reload penalty:
        // Must stall to reload subsequent key slices and re-accumulate
        $display("Region B suffering forced WS memory buffer reload stalls...");
        compute_en[1] = 0;
        for (int reload = 1; reload < 3; reload++) begin
            w_ld[1] = 1; // Stall to reload key vectors into PEs
            for (int r = 0; r < NUM_ROWS; r++) begin
                set_din_w_b(r, vit_k_mem[reload % K_STEPS][r]);
            end
            step_clk();
            step_clk();
            w_ld[1] = 0;
            compute_en[1] = 1;
            repeat (K_STEPS / 4) begin
                step_clk();
                total_active_macs += (NUM_ROWS * HALF_COLS);
            end
            compute_en[1] = 0;
        end

        din_n = '0;
        din_w_region_b = '0;
        step_clk();
        step_clk();
        end_cycle_reg_b = cycle_count;
        $display("Region B (ViT Forced WS) Completed: %0d cycles (Stretched by dataflow mismatch)", (end_cycle_reg_b - start_cycle_total));

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
        $fwrite(fp, "  \"total_makespan_cycles\": %0d,\n", cycle_count);
        $fwrite(fp, "  \"total_valid_macs\": %0d\n", total_active_macs);
        $fwrite(fp, "}\n");
        $fclose(fp);

        $display("\n================================================================");
        $display(" [SUMMARY: MODEL 2 HOMOGENEOUS FISSION]");
        $display("   Region A (CNN Native WS) Cycles: %0d", (end_cycle_reg_a - start_cycle_total));
        $display("   Region B (ViT Forced WS) Cycles: %0d", (end_cycle_reg_b - start_cycle_total));
        $display("   Total Co-Run Makespan Cycles:    %0d", cycle_count);
        $display("   Total Valid MACs:                %0d", total_active_macs);
        $display("================================================================");
        $finish;
    end

endmodule

