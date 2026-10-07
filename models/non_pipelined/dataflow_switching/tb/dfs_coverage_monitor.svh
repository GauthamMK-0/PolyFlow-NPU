// dfs_coverage_monitor.svh — Dual-Environment Functional Coverage Engine for Single-Tenant Dataflow Switching (Model 1)
// Provides native IEEE 1800 covergroups for Cadence Xcelium and an active bin tracker for Verilator/batch logs.

`ifndef VERILATOR
`ifndef __ICARUS__
    // Standard IEEE 1800 SystemVerilog Covergroup for Cadence Xcelium / IMC / UCDB
    covergroup cg_dataflow_switching @(posedge clk);
        cp_dataflow_mode: coverpoint cfg_dataflow_mode {
            bins ws = {2'b00};
            bins os = {2'b01};
            bins is = {2'b10};
        }

        cp_compute_en: coverpoint tile_compute_en {
            bins disabled = {1'b0};
            bins enabled  = {1'b1};
        }

        cp_w_ld: coverpoint tile_w_ld {
            bins inactive = {1'b0};
            bins active   = {1'b1};
        }

        cp_acc_clr: coverpoint tile_acc_clr {
            bins run   = {1'b0};
            bins clear = {1'b1};
        }

        cross_df_compute: cross cp_dataflow_mode, cp_compute_en;
    endgroup

    cg_dataflow_switching cg_dfs_inst = new();
`endif
`endif

// Universal Active Coverage Monitor (Executes in all simulators: Verilator, Icarus, Xcelium)
int cov_df_mode_hits [3];
int cov_compute_hits [2];
int cov_w_ld_hits [2];
int cov_acc_clr_hits [2];
int cov_cross_df_compute_hits [3][2];

task automatic sample_coverage();
    if (rst_n) begin
        // Sample dataflow mode (0=WS, 1=OS, 2=IS)
        if (cfg_dataflow_mode <= 2'd2) cov_df_mode_hits[cfg_dataflow_mode]++;

        // Sample compute enable (0, 1)
        cov_compute_hits[tile_compute_en]++;

        // Sample weight load (0, 1)
        cov_w_ld_hits[tile_w_ld]++;

        // Sample acc clear (0, 1)
        cov_acc_clr_hits[tile_acc_clr]++;

        // Cross dataflow and compute
        if (cfg_dataflow_mode <= 2'd2) begin
            cov_cross_df_compute_hits[cfg_dataflow_mode][tile_compute_en]++;
        end
    end
endtask

task automatic print_functional_coverage_report();
    int total_bins;
    int hit_bins;
    real cov_pct;

    total_bins = 3 + 2 + 2 + 2 + 6; // Dataflows (3) + Compute (2) + W_Ld (2) + Acc_Clr (2) + Cross (6) = 15
    hit_bins = 0;

    for (int i = 0; i < 3; i++) if (cov_df_mode_hits[i] > 0) hit_bins++;
    for (int i = 0; i < 2; i++) if (cov_compute_hits[i] > 0) hit_bins++;
    for (int i = 0; i < 2; i++) if (cov_w_ld_hits[i] > 0) hit_bins++;
    for (int i = 0; i < 2; i++) if (cov_acc_clr_hits[i] > 0) hit_bins++;
    for (int i = 0; i < 3; i++) begin
        for (int j = 0; j < 2; j++) begin
            if (cov_cross_df_compute_hits[i][j] > 0) hit_bins++;
        end
    end

    cov_pct = (real'(hit_bins) / real'(total_bins)) * 100.0;

    $display("\n================================================================");
    $display("     FUNCTIONAL COVERAGE REPORT (Dataflow Switching / Model 1)   ");
    $display("================================================================");
    $display(" Metric Group                   Covered Bins / Total    Coverage ");
    $display(" ---------------------------------------------------------------");
    $display(" Runtime Dataflow Modes (WS/OS/IS)      :  %0d / 3 bins       %3.0f%%",
             count_df(), (real'(count_df())/3.0)*100.0);
    $display(" Compute Enable States (Gated/Active)   :  %0d / 2 bins       %3.0f%%",
             count_compute(), (real'(count_compute())/2.0)*100.0);
    $display(" Stationary Preload Strobes (W_LD)      :  %0d / 2 bins       %3.0f%%",
             count_w_ld(), (real'(count_w_ld())/2.0)*100.0);
    $display(" Accumulator Clear Strobes (ACC_CLR)    :  %0d / 2 bins       %3.0f%%",
             count_acc_clr(), (real'(count_acc_clr())/2.0)*100.0);
    $display(" Cross Dataflow x Compute Transitions   :  %0d / 6 bins       %3.0f%%",
             count_cross(), (real'(count_cross())/6.0)*100.0);
    $display(" ---------------------------------------------------------------");
    $display(" TOTAL FUNCTIONAL COVERAGE              :  %0d / %0d bins     %5.1f%%",
             hit_bins, total_bins, cov_pct);
    $display("================================================================");
endtask

function automatic int count_df();
    int c;
    c = 0;
    for (int i = 0; i < 3; i++) if (cov_df_mode_hits[i] > 0) c++;
    return c;
endfunction

function automatic int count_compute();
    int c;
    c = 0;
    for (int i = 0; i < 2; i++) if (cov_compute_hits[i] > 0) c++;
    return c;
endfunction

function automatic int count_w_ld();
    int c;
    c = 0;
    for (int i = 0; i < 2; i++) if (cov_w_ld_hits[i] > 0) c++;
    return c;
endfunction

function automatic int count_acc_clr();
    int c;
    c = 0;
    for (int i = 0; i < 2; i++) if (cov_acc_clr_hits[i] > 0) c++;
    return c;
endfunction

function automatic int count_cross();
    int c;
    c = 0;
    for (int i = 0; i < 3; i++) begin
        for (int j = 0; j < 2; j++) begin
            if (cov_cross_df_compute_hits[i][j] > 0) c++;
        end
    end
    return c;
endfunction
