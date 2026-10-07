// sfa_coverage_monitor.svh — Dual-Environment Functional Coverage Engine for Homogeneous Spatial Fission (Model 2)
// Provides native IEEE 1800 covergroups for Cadence Xcelium and an active bin tracker for Verilator/batch logs.

`ifndef VERILATOR
`ifndef __ICARUS__
    // Standard IEEE 1800 SystemVerilog Covergroup for Cadence Xcelium / IMC / UCDB
    covergroup cg_spatial_fission @(posedge clk);
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

        cp_compute_en: coverpoint compute_en {
            bins idle     = {2'b00};
            bins a_only   = {2'b01};
            bins b_only   = {2'b10};
            bins coexec   = {2'b11};
        }
    endgroup

    cg_spatial_fission cg_sfa_inst = new();
`endif
`endif

// Universal Active Coverage Monitor (Executes in all simulators: Verilator, Icarus, Xcelium)
int cov_split_hits [5];
int cov_phase_a_hits [4];
int cov_phase_b_hits [4];
int cov_compute_hits [4];
int cov_contention_events;
int cov_scrub_events;

task automatic sample_coverage();
    if (rst_n) begin
        // Sample split configuration (0..4)
        if (cfg_split_col <= 4'd4) cov_split_hits[3'(cfg_split_col)]++;

        // Sample EPPA phases (0..3)
        cov_phase_a_hits[phase_tag[1:0]]++;
        cov_phase_b_hits[phase_tag[3:2]]++;

        // Sample compute enable modes (0..3)
        cov_compute_hits[compute_en]++;

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

    total_bins = 5 + 4 + 4 + 4 + 1 + 1; // Splits (5) + Phases (8) + Compute (4) + Contention (1) + Scrub (1) = 19
    hit_bins = 0;

    for (int i = 0; i < 5; i++) if (cov_split_hits[i] > 0) hit_bins++;
    for (int i = 0; i < 4; i++) if (cov_phase_a_hits[i] > 0) hit_bins++;
    for (int i = 0; i < 4; i++) if (cov_phase_b_hits[i] > 0) hit_bins++;
    for (int i = 0; i < 4; i++) if (cov_compute_hits[i] > 0) hit_bins++;
    if (cov_contention_events > 0) hit_bins++;
    if (cov_scrub_events > 0) hit_bins++;

    cov_pct = (real'(hit_bins) / real'(total_bins)) * 100.0;

    $display("\n================================================================");
    $display("       FUNCTIONAL COVERAGE REPORT (Spatial Fission / Model 2)    ");
    $display("================================================================");
    $display(" Metric Group                   Covered Bins / Total    Coverage ");
    $display(" ---------------------------------------------------------------");
    $display(" Dynamic Fission Splits (Col 0..4)      :  %0d / 5 bins       %3.0f%%",
             count_splits(), (real'(count_splits())/5.0)*100.0);
    $display(" EPPA Memory Phase Tags (All Phases)    :  %0d / 8 bins       %3.0f%%",
             count_phases(), (real'(count_phases())/8.0)*100.0);
    $display(" Multi-Tenant Compute States (WS Co-Ex) :  %0d / 4 bins       %3.0f%%",
             count_compute(), (real'(count_compute())/4.0)*100.0);
    $display(" Multi-Tenant Memory Contention Events  :  %0d / 1 bins       %3.0f%%",
             (cov_contention_events > 0 ? 1 : 0), (cov_contention_events > 0 ? 100.0 : 0.0));
    $display(" 4-Cycle Hardware Scrubbing Transitions :  %0d / 1 bins       %3.0f%%",
             (cov_scrub_events > 0 ? 1 : 0), (cov_scrub_events > 0 ? 100.0 : 0.0));
    $display(" ---------------------------------------------------------------");
    $display(" TOTAL FUNCTIONAL COVERAGE              :  %0d / %0d bins     %5.1f%%",
             hit_bins, total_bins, cov_pct);
    $display("================================================================");
endtask

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

function automatic int count_compute();
    int c;
    c = 0;
    for (int i = 0; i < 4; i++) if (cov_compute_hits[i] > 0) c++;
    return c;
endfunction
