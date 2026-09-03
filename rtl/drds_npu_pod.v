module drds_npu_pod #(
    parameter int BW_W        = 8,
    parameter int EPOCH_W     = 8,
    parameter int SCRUB_CYC   = 4,
    parameter int NUM_BANKS   = 4,
    parameter int NUM_COLS    = 16,
    parameter int NUM_ROWS    = 16,
    parameter int DATA_W      = 8,
    parameter int ACC_W       = 32,
    parameter int LIFETIME_W  = 4,
    parameter int REGION_W    = 1,
    parameter int NUM_REGIONS = 2
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Dispatch-Time Spatial Fission Configuration
    input  logic [3:0]              cfg_split_col,
    input  logic                    cfg_update_strobe,

    // Region Control & Arbitration
    input  logic [2*NUM_REGIONS-1:0] phase_tag,
    input  logic [NUM_BANKS-1:0]     token_req_A,
    input  logic [NUM_BANKS-1:0]     token_req_B,
    input  logic [NUM_BANKS-1:0]     token_release_A,
    input  logic [NUM_BANKS-1:0]     token_release_B,
    input  logic [NUM_BANKS-1:0]     role_reassign,
    input  logic [NUM_BANKS-1:0]     new_region_id_per_bank,
    input  logic [2*NUM_BANKS-1:0]   new_role_per_bank,

    // PE Array Control (simplified - broadcast per column)
    input  logic [1:0]              dataflow_mode [NUM_COLS-1:0],
    input  logic [3:0]              route_sel     [NUM_COLS-1:0],
    input  logic                    w_ld          [NUM_COLS-1:0],
    input  logic                    acc_clr       [NUM_COLS-1:0],
    input  logic                    lifetime_ld   [NUM_COLS-1:0],
    input  logic [LIFETIME_W-1:0]   lifetime_init [NUM_COLS-1:0],

    // PE Array Data I/O (column-wise)
    input  logic [DATA_W-1:0]       din_n [NUM_COLS-1:0],
    input  logic [DATA_W-1:0]       din_s [NUM_COLS-1:0],
    input  logic [DATA_W-1:0]       din_w [NUM_ROWS-1:0],
    output logic [DATA_W-1:0]       dout_n [NUM_COLS-1:0],
    output logic [DATA_W-1:0]       dout_s [NUM_COLS-1:0],
    output logic [DATA_W-1:0]       dout_e [NUM_ROWS-1:0],
    output logic [ACC_W-1:0]        acc_out [NUM_COLS-1:0],

    // Bus / DMA & Status Outputs
    output logic [NUM_REGIONS*BW_W-1:0] bw_alloc,
    output logic [NUM_REGIONS-1:0]      reconfig_urgent,
    output logic [NUM_BANKS-1:0]        bank_role_clear_bus,
    output logic [NUM_BANKS-1:0]        scrub_active_bus,
    output logic [NUM_COLS-1:0]         pe_region_id_mask,
    output logic [NUM_COLS-1:0]         pe_reassign_bus,
    output logic [NUM_COLS-1:0]         pe_bank_role_stale
);

    // Fission Decoder
    logic [NUM_COLS-1:0] region_id_mask;
    logic [NUM_COLS-1:0] region_reassign_bus;

    pod_fission_decoder #(
        .NUM_COLS(NUM_COLS)
    ) u_fission_dec (
        .clk                (clk),
        .rst_n              (rst_n),
        .cfg_split_col      (cfg_split_col),
        .cfg_update_strobe  (cfg_update_strobe),
        .region_id_mask     (region_id_mask),
        .region_reassign_bus(region_reassign_bus)
    );

    assign pe_region_id_mask = region_id_mask;
    assign pe_reassign_bus   = region_reassign_bus;

    // EPPA Arbiter
    eppa_arbiter #(
        .NUM_REGIONS(NUM_REGIONS),
        .BW_W(BW_W)
    ) u_eppa (
        .clk            (clk),
        .rst_n          (rst_n),
        .phase_tag      (phase_tag),
        .bw_alloc       (bw_alloc),
        .reconfig_urgent(reconfig_urgent)
    );

    // PE Array Grid
    logic [REGION_W-1:0] pe_region_id [NUM_COLS-1:0];
    logic                pe_region_reassign [NUM_COLS-1:0];
    logic                pe_bank_role_clear [NUM_COLS-1:0];
    logic                pe_bank_role_stale_int [NUM_COLS-1:0];

    // Map region_id_mask to per-PE region_id and region_reassign
    for (genvar c = 0; c < NUM_COLS; c++) begin : pe_ctrl_map
        assign pe_region_id[c]       = region_id_mask[c];
        assign pe_region_reassign[c] = region_reassign_bus[c];
        assign pe_bank_role_clear[c] = bank_role_clear_bus[0]; // Simplified: all PEs in column get same clear
    end

    hdf_array_grid #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .LIFETIME_W(LIFETIME_W),
        .REGION_W(REGION_W),
        .NUM_ROWS(NUM_ROWS),
        .NUM_COLS(NUM_COLS)
    ) u_array_grid (
        .clk(clk),
        .rst_n(rst_n),
        .din_n(din_n),
        .din_s(din_s),
        .din_w(din_w),
        .dout_n(dout_n),
        .dout_s(dout_s),
        .dout_e(dout_e),
        .acc_out(acc_out),
        .dataflow_mode(dataflow_mode),
        .region_id(pe_region_id),
        .region_reassign(pe_region_reassign),
        .route_sel(route_sel),
        .w_ld(w_ld),
        .acc_clr(acc_clr),
        .lifetime_ld(lifetime_ld),
        .lifetime_init(lifetime_init),
        .bank_role_stale(pe_bank_role_stale_int),
        .bank_role_clear(pe_bank_role_clear),
        .region_id_mask(region_id_mask)
    );

    assign pe_bank_role_stale = pe_bank_role_stale_int;

    // Per-Bank OTP & Scrub Controllers
    generate
        for (genvar b = 0; b < NUM_BANKS; b++) begin : bank_ctrl
            logic scrub_wire, clr_wire;
            logic [NUM_REGIONS-1:0] token_req_bank;
            logic [NUM_REGIONS-1:0] token_release_bank;

            assign token_req_bank[0] = token_req_A[b];
            assign token_req_bank[1] = token_req_B[b];
            assign token_release_bank[0] = token_release_A[b];
            assign token_release_bank[1] = token_release_B[b];

            otp_token_fsm #(
                .NUM_REGIONS(NUM_REGIONS),
                .REGION_W(REGION_W),
                .EPOCH_W(EPOCH_W)
            ) u_otp (
                .clk          (clk),
                .rst_n        (rst_n),
                .token_req    (token_req_bank),
                .token_release(token_release_bank),
                .scrub_active (scrub_wire),
                .token_owner  (),
                .token_held   (),
                .grant        ()
            );

            pod_bank_scrub #(
                .REGION_W(REGION_W),
                .SCRUB_CYC(SCRUB_CYC)
            ) u_scrub (
                .clk            (clk),
                .rst_n          (rst_n),
                .role_reassign  (role_reassign[b]),
                .new_region_id  (new_region_id_per_bank[b]),
                .new_role       (new_role_per_bank[2*b +: 2]),
                .scrub_active   (scrub_wire),
                .bank_role_clear(clr_wire),
                .region_owner   (),
                .role_tag       ()
            );

            assign scrub_active_bus[b]    = scrub_wire;
            assign bank_role_clear_bus[b] = clr_wire;
        end
    endgenerate

endmodule