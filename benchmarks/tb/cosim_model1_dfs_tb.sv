// cosim_model1_dfs_tb.sv — Cycle-Accurate Co-Simulation Testbench for Model 1 (ReDas Baseline)
// Executes sequential single-tenant workloads: CNN (WS) -> Flush/Reconfig -> ViT Attention (OS).
// Measures exact execution cycles, valid MAC counts, and dumps accumulators for accuracy verification.

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

module cosim_model1_dfs_tb;

    localparam int DATA_W    = 8;
    localparam int ACC_W     = 32;
    localparam int NUM_ROWS  = `NUM_ROWS;
    localparam int NUM_COLS  = `NUM_COLS;
    localparam int HALF_COLS = NUM_COLS / 2;
    localparam int K_STEPS   = `K_STEPS;

    logic clk;
    logic rst_n;

    logic [1:0]                         cfg_dataflow_mode;
    logic                               tile_w_ld;
    logic                               tile_acc_clr;
    logic                               tile_compute_en;

    logic [NUM_COLS*DATA_W-1:0]         din_n;
    logic [NUM_ROWS*DATA_W-1:0]         din_w;
    wire  [NUM_COLS*DATA_W-1:0]         dout_s;
    wire  [NUM_ROWS*DATA_W-1:0]         dout_e;
    wire  [NUM_ROWS*NUM_COLS*ACC_W-1:0] acc_out_flat;

    // Workload memory buffers
    logic [DATA_W-1:0] cnn_weights_mem [0:NUM_ROWS-1][0:NUM_COLS-1];
    logic [DATA_W-1:0] cnn_inputs_mem  [0:K_STEPS-1][0:NUM_ROWS-1];
    logic [DATA_W-1:0] vit_q_mem       [0:K_STEPS-1][0:NUM_COLS-1];
    logic [DATA_W-1:0] vit_k_mem       [0:K_STEPS-1][0:NUM_ROWS-1];

    // Execution cycle metrics
    int cycle_count = 0;
    int start_cycle_cnn = 0;
    int end_cycle_cnn = 0;
    int start_cycle_vit = 0;
    int end_cycle_vit = 0;
    int total_active_macs = 0;

    // Helper to get PE accumulator
    function automatic logic signed [ACC_W-1:0] get_pe_acc(int r, int c);
        return acc_out_flat[(r*NUM_COLS + c)*ACC_W +: ACC_W];
    endfunction

    task automatic set_din_n(int c, logic [DATA_W-1:0] val);
        din_n[c*DATA_W +: DATA_W] = val;
    endtask

    task automatic set_din_w(int r, logic [DATA_W-1:0] val);
        din_w[r*DATA_W +: DATA_W] = val;
    endtask

    // DUT Instantiation
    dfs_top #(
        .DATA_W  (DATA_W),
        .ACC_W   (ACC_W),
        .NUM_ROWS(NUM_ROWS),
        .NUM_COLS(NUM_COLS)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .cfg_dataflow_mode(cfg_dataflow_mode),
        .tile_w_ld        (tile_w_ld),
        .tile_acc_clr     (tile_acc_clr),
        .tile_compute_en  (tile_compute_en),
        .din_n            (din_n),
        .din_w            (din_w),
        .dout_s           (dout_s),
        .dout_e           (dout_e),
        .acc_out_flat     (acc_out_flat)
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
        $display(" [BENCHMARK] Model 1: Sequential Dataflow Switching (ReDas) [%0dx%0d]", NUM_ROWS, NUM_COLS);
        $display(" Workload: Tenant A CNN (WS) -> Reconfig/Flush -> Tenant B ViT (OS)");
        $display("================================================================");

        // Load quantized INT8 real-world data files
        $readmemh({"benchmarks/data/", `SCALE_NAME, "/cnn_weights.mem"}, cnn_weights_mem);
        $readmemh({"benchmarks/data/", `SCALE_NAME, "/cnn_inputs.mem"},  cnn_inputs_mem);
        $readmemh({"benchmarks/data/", `SCALE_NAME, "/vit_q.mem"},       vit_q_mem);
        $readmemh({"benchmarks/data/", `SCALE_NAME, "/vit_k.mem"},       vit_k_mem);

        // Reset
        rst_n             = 0;
        cfg_dataflow_mode = 2'b00; // WS mode
        tile_w_ld         = 0;
        tile_acc_clr      = 1;
        tile_compute_en   = 0;
        din_n             = '0;
        din_w             = '0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        #1;
        cycle_count = 0;

        // -------------------------------------------------------------
        // PHASE 1: Tenant A — CNN Layer in Weight-Stationary (WS) Mode
        // -------------------------------------------------------------
        start_cycle_cnn = cycle_count;

        // Cycle 1: Clear accumulators & set WS mode
        cfg_dataflow_mode = 2'b00;
        tile_acc_clr      = 1;
        step_clk();
        tile_acc_clr      = 0;

        // Preload stationary weights: shift West-to-East across HALF_COLS columns
        tile_w_ld = 1;
        for (int step = HALF_COLS - 1; step >= 0; step--) begin
            for (int r = 0; r < NUM_ROWS; r++) begin
                set_din_w(r, cnn_weights_mem[r][step]);
            end
            step_clk();
        end
        tile_w_ld = 0;

        // Stream CNN activations across all rows (K_STEPS cycles)
        tile_compute_en = 1;
        for (int k = 0; k < K_STEPS; k++) begin
            for (int r = 0; r < NUM_ROWS; r++) begin
                set_din_w(r, cnn_inputs_mem[k][r]);
            end
            step_clk();
            total_active_macs += (NUM_ROWS * HALF_COLS);
        end

        // Cycle K+3: Drain final product register into accumulator
        din_w           = '0;
        tile_compute_en = 0;
        step_clk();

        end_cycle_cnn = cycle_count;
        $display("Tenant A (CNN Solo WS) Completed: %0d cycles", (end_cycle_cnn - start_cycle_cnn));

        // Dump CNN solo output to result file (NUM_ROWS x HALF_COLS)
        fp = $fopen({"benchmarks/results/", `SCALE_NAME, "/m1_cnn_hw_output.txt"}, "w");
        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = 0; c < HALF_COLS; c++) begin
                $fwrite(fp, "%0d ", get_pe_acc(r, c));
            end
            $fwrite(fp, "\n");
        end
        $fclose(fp);

        // -------------------------------------------------------------
        // PHASE 2 & 3: Reconfiguration (WS -> OS) & Tenant B ViT Attention
        // -------------------------------------------------------------
        start_cycle_vit = cycle_count;

        // Cycle 1 of Phase 2/3: Switch dataflow mode to OS & clear accumulators
        tile_acc_clr      = 1;
        cfg_dataflow_mode = 2'b01; // Switch to OS
        step_clk();
        tile_acc_clr      = 0;

        // Cycles 2 .. K+1: Stream ViT Q and K vectors (K_STEPS cycles)
        // Tenant B computes NUM_ROWS x HALF_COLS outputs in cols [HALF_COLS..NUM_COLS-1].
        tile_compute_en = 1;
        for (int k = 0; k < K_STEPS; k++) begin
            for (int c = 0; c < HALF_COLS; c++) begin
                set_din_n(c, 8'd0);
            end
            for (int c = HALF_COLS; c < NUM_COLS; c++) begin
                set_din_n(c, vit_q_mem[k][c]);
            end
            for (int r = 0; r < NUM_ROWS; r++) begin
                set_din_w(r, vit_k_mem[k][r]);
            end
            step_clk();
            total_active_macs += (NUM_ROWS * HALF_COLS);
        end

        // Cycle K+2: Drain final product register into accumulator
        din_n           = '0;
        din_w           = '0;
        tile_compute_en = 0;
        step_clk();

        end_cycle_vit = cycle_count;
        $display("Tenant B (ViT Solo OS) Completed: %0d cycles (Finish time: %0d)", (end_cycle_vit - start_cycle_vit), end_cycle_vit);

        // Dump ViT solo output (NUM_ROWS x HALF_COLS)
        fp = $fopen({"benchmarks/results/", `SCALE_NAME, "/m1_vit_hw_output.txt"}, "w");
        for (int r = 0; r < NUM_ROWS; r++) begin
            for (int c = HALF_COLS; c < NUM_COLS; c++) begin
                $fwrite(fp, "%0d ", get_pe_acc(r, c));
            end
            $fwrite(fp, "\n");
        end
        $fclose(fp);

        // Dump execution metrics JSON
        fp = $fopen({"benchmarks/results/", `SCALE_NAME, "/m1_metrics.json"}, "w");
        $fwrite(fp, "{\n");
        $fwrite(fp, "  \"model\": \"Model 1 (Sequential Switching)\",\n");
        $fwrite(fp, "  \"scale\": \"%s\",\n", `SCALE_NAME);
        $fwrite(fp, "  \"cnn_cycles\": %0d,\n", (end_cycle_cnn - start_cycle_cnn));
        $fwrite(fp, "  \"vit_cycles\": %0d,\n", (end_cycle_vit - start_cycle_vit));
        $fwrite(fp, "  \"reg_a_turnaround_cycles\": %0d,\n", end_cycle_cnn);
        $fwrite(fp, "  \"reg_b_turnaround_cycles\": %0d,\n", end_cycle_vit);
        $fwrite(fp, "  \"total_makespan_cycles\": %0d,\n", end_cycle_vit);
        $fwrite(fp, "  \"total_valid_macs\": %0d\n", total_active_macs);
        $fwrite(fp, "}\n");
        $fclose(fp);

        $display("\n================================================================");
        $display(" [SUMMARY: MODEL 1 SEQUENTIAL]");
        $display("   CNN Solo Duration:      %0d cycles (Turnaround: %0d)", (end_cycle_cnn - start_cycle_cnn), end_cycle_cnn);
        $display("   ViT Solo Duration:      %0d cycles (Turnaround: %0d)", (end_cycle_vit - start_cycle_vit), end_cycle_vit);
        $display("   Total Makespan Cycles:  %0d", end_cycle_vit);
        $display("   Total Useful MACs:      %0d", total_active_macs);
        $display("================================================================");
        $finish;
    end

endmodule
