// hdf_coverage_monitor.svh — Dual-Environment Functional Coverage Engine for PolyFlow-NPU
// Provides native IEEE 1800 covergroups for Cadence Xcelium and an active bin tracker for Verilator/batch logs.

`ifndef VERILATOR
`ifndef __ICARUS__
    // Standard IEEE 1800 SystemVerilog Covergroup for Cadence Xcelium / IMC / UCDB
    covergroup cg_polyflow @(posedge clk);
        cp_dataflow_a: coverpoint dataflow_mode[1:0] {
            bins ws = {2'b00};
            bins os = {2'b01};
            bins is = {2'b10};
        }
        cp_dataflow_b: coverpoint dataflow_mode[3:2] {
            bins ws = {2'b00};
            bins os = {2'b01};
            bins is = {2'b10};
        }
        cross_hetero_df: cross cp_dataflow_a, cp_dataflow_b;

        cp_split_col: coverpoint cfg_split_col {
            bins all_b  = {4'd0};
            bins asym_1 = {4'd1};
            bins sym_2  = {4'd2};
            bins asym_3 = {4'd3};
            bins all_a  = {4'd4};
        }

        cp_phase_a: coverpoint phase_tag[1:0] {
            bins burst    = {2'b00};
            bins idle     = {2'b01};
            bins stream   = {2'b10};
            bins reconfig = {2'b11};
        }
        cp_phase_b: coverpoint phase_tag[3:2] {
            bins burst    = {2'b00};
            bins idle     = {2'b01};
            bins stream   = {2'b10};
            bins reconfig = {2'b11};
        }
        cross_eppa_phases: cross cp_phase_a, cp_phase_b;

        cp_bank0_grant: coverpoint token_grant_bus[1:0] {
            bins req_a = {2'b01};
            bins req_b = {2'b10};
            bins none  = {2'b00};
        }
        cp_bank1_grant: coverpoint token_grant_bus[3:2] {
            bins req_a = {2'b01};
            bins req_b = {2'b10};
            bins none  = {2'b00};
        }

        cp_scrub_b0: coverpoint scrub_active_bus[0];
        cp_scrub_b1: coverpoint scrub_active_bus[1];
    endgroup

    cg_polyflow cg_inst = new();
`endif
`endif

// Universal Active Coverage Monitor (Executes in all simulators: Verilator, Icarus, Xcelium)
int cov_df_a_hits [3];
int cov_df_b_hits [3];
int cov_cross_df_hits [3][3];
int cov_split_hits [5];
int cov_phase_a_hits [4];
int cov_phase_b_hits [4];
int cov_contention_events;
int cov_scrub_events;

task automatic sample_coverage();
    if (rst_n) begin
        // Sample dataflows (0=WS, 1=OS, 2=IS)
        if (dataflow_mode[1:0] <= 2'd2) cov_df_a_hits[dataflow_mode[1:0]]++;
        if (dataflow_mode[3:2] <= 2'd2) cov_df_b_hits[dataflow_mode[3:2]]++;
        if (dataflow_mode[1:0] <= 2'd2 && dataflow_mode[3:2] <= 2'd2) begin
            cov_cross_df_hits[dataflow_mode[1:0]][dataflow_mode[3:2]]++;
        end

        // Sample split configuration (0..4)
        if (cfg_split_col <= 4'd4) cov_split_hits[3'(cfg_split_col)]++;

        // Sample EPPA phases (0..3)
        cov_phase_a_hits[phase_tag[1:0]]++;
        cov_phase_b_hits[phase_tag[3:2]]++;

        // Sample contention
        if (token_req_A[0] && token_req_B[0]) cov_contention_events++;

        // Sample scrub active
        if (|scrub_active_bus) cov_scrub_events++;
    end
endtask

task automatic print_functional_coverage_report();
    int total_bins;
    int hit_bins;
    real cov_pct;

    total_bins = 3 + 3 + 9 + 5 + 4 + 4 + 2; // Dataflows + Cross + Splits + Phases + Contention/Scrub
    hit_bins = 0;

    for (int i = 0; i < 3; i++) if (cov_df_a_hits[i] > 0) hit_bins++;
    for (int i = 0; i < 3; i++) if (cov_df_b_hits[i] > 0) hit_bins++;
    for (int i = 0; i < 3; i++) begin
        for (int j = 0; j < 3; j++) begin
            if (cov_cross_df_hits[i][j] > 0) hit_bins++;
        end
    end
    for (int i = 0; i < 5; i++) if (cov_split_hits[i] > 0) hit_bins++;
    for (int i = 0; i < 4; i++) if (cov_phase_a_hits[i] > 0) hit_bins++;
    for (int i = 0; i < 4; i++) if (cov_phase_b_hits[i] > 0) hit_bins++;
    if (cov_contention_events > 0) hit_bins++;
    if (cov_scrub_events > 0) hit_bins++;

    cov_pct = (real'(hit_bins) / real'(total_bins)) * 100.0;

    $display("\n================================================================");
    $display("       FUNCTIONAL COVERAGE REPORT (PolyFlow-NPU / Model 3)       ");
    $display("================================================================");
    $display(" Metric Group                   Covered Bins / Total    Coverage ");
    $display(" ---------------------------------------------------------------");
    $display(" Region A Dataflow Modes (WS/OS/IS)     :  %0d / 3 bins       %3.0f%%",
             count_df_a(), (real'(count_df_a())/3.0)*100.0);
    $display(" Region B Dataflow Modes (WS/OS/IS)     :  %0d / 3 bins       %3.0f%%",
             count_df_b(), (real'(count_df_b())/3.0)*100.0);
    $display(" Cross Heterogeneous Dataflow Combos    :  %0d / 9 bins       %3.0f%%",
             count_cross_df(), (real'(count_cross_df())/9.0)*100.0);
    $display(" Dynamic Fission Splits (Col 0..4)      :  %0d / 5 bins       %3.0f%%",
             count_splits(), (real'(count_splits())/5.0)*100.0);
    $display(" EPPA Memory Phase Tags (All Phases)    :  %0d / 8 bins       %3.0f%%",
             count_phases(), (real'(count_phases())/8.0)*100.0);
    $display(" Multi-Tenant Memory Contention Events  :  %0d / 1 bins       %3.0f%%",
             (cov_contention_events > 0 ? 1 : 0), (cov_contention_events > 0 ? 100.0 : 0.0));
    $display(" 4-Cycle Hardware Scrubbing Transitions :  %0d / 1 bins       %3.0f%%",
             (cov_scrub_events > 0 ? 1 : 0), (cov_scrub_events > 0 ? 100.0 : 0.0));
    $display(" ---------------------------------------------------------------");
    $display(" TOTAL FUNCTIONAL COVERAGE              :  %0d / %0d bins     %5.1f%%",
             hit_bins, total_bins, cov_pct);
    $display("================================================================");
endtask

function automatic int count_df_a();
    int c;
    c = 0;
    for (int i = 0; i < 3; i++) if (cov_df_a_hits[i] > 0) c++;
    return c;
endfunction

function automatic int count_df_b();
    int c;
    c = 0;
    for (int i = 0; i < 3; i++) if (cov_df_b_hits[i] > 0) c++;
    return c;
endfunction

function automatic int count_cross_df();
    int c;
    c = 0;
    for (int i = 0; i < 3; i++) begin
        for (int j = 0; j < 3; j++) begin
            if (cov_cross_df_hits[i][j] > 0) c++;
        end
    end
    return c;
endfunction

function automatic int count_splits();
    int c;
    c = 0;
    for (int i = 0; i < 5; i++) if (cov_split_hits[i] > 0) c++;
    return c;
endfunction

function automatic int count_phases();
    int c;
    c = 0;
    for (int i = 0; i < 4; i++) if (cov_phase_a_hits[i] > 0) c++;
    for (int i = 0; i < 4; i++) if (cov_phase_b_hits[i] > 0) c++;
    return c;
endfunction
