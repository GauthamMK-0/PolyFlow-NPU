module hdf_array_grid #(
    parameter int DATA_W      = 8,
    parameter int ACC_W       = 32,
    parameter int LIFETIME_W  = 4,
    parameter int REGION_W    = 1,
    parameter int NUM_ROWS    = 16,
    parameter int NUM_COLS    = 16
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Global mesh inputs (from memory/controllers)
    input  logic [DATA_W-1:0]       din_n [NUM_COLS-1:0],
    input  logic [DATA_W-1:0]       din_s [NUM_COLS-1:0],
    input  logic [DATA_W-1:0]       din_w [NUM_ROWS-1:0],

    // Global mesh outputs (to memory/controllers)
    output logic [DATA_W-1:0]       dout_n [NUM_COLS-1:0],
    output logic [DATA_W-1:0]       dout_s [NUM_COLS-1:0],
    output logic [DATA_W-1:0]       dout_e [NUM_ROWS-1:0],

    // Full accumulator outputs per column (for column-wise collection)
    output logic [ACC_W-1:0]        acc_out [NUM_COLS-1:0],

    // Per-PE control (broadcast or per-column)
    input  logic [1:0]              dataflow_mode [NUM_COLS-1:0],
    input  logic [REGION_W-1:0]     region_id     [NUM_COLS-1:0],
    input  logic                    region_reassign [NUM_COLS-1:0],
    input  logic [3:0]              route_sel     [NUM_COLS-1:0],
    input  logic                    w_ld          [NUM_COLS-1:0],
    input  logic                    acc_clr       [NUM_COLS-1:0],
    input  logic                    lifetime_ld   [NUM_COLS-1:0],
    input  logic [LIFETIME_W-1:0]   lifetime_init [NUM_COLS-1:0],
    output logic                    bank_role_stale [NUM_COLS-1:0],
    input  logic                    bank_role_clear [NUM_COLS-1:0],

    // Boundary isolation control
    input  logic [NUM_COLS-1:0]     region_id_mask
);

    // Internal mesh signals
    logic [DATA_W-1:0] mesh_n [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic [DATA_W-1:0] mesh_s [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic [DATA_W-1:0] mesh_e [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic [DATA_W-1:0] mesh_w [NUM_ROWS-1:0][NUM_COLS-1:0];

    // PE input/output signals
    logic [DATA_W-1:0] pe_din_n  [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic [DATA_W-1:0] pe_din_s  [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic [DATA_W-1:0] pe_din_e  [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic [DATA_W-1:0] pe_din_w  [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic [DATA_W-1:0] pe_dout_n [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic [DATA_W-1:0] pe_dout_s [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic [DATA_W-1:0] pe_dout_e [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic [DATA_W-1:0] pe_dout_w [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic [ACC_W-1:0]  pe_acc_out [NUM_ROWS-1:0][NUM_COLS-1:0];
    logic              pe_bank_role_stale [NUM_ROWS-1:0][NUM_COLS-1:0];

    // North inputs: row 0 from din_n, others from mesh_s of row above
    for (genvar c = 0; c < NUM_COLS; c++) begin : north_input_gen
        assign pe_din_n[0][c] = din_n[c];
    end
    for (genvar r = 1; r < NUM_ROWS; r++) begin : north_input_gen_r
        for (genvar c = 0; c < NUM_COLS; c++) begin : north_input_gen_c
            assign pe_din_n[r][c] = mesh_s[r-1][c];
        end
    end

    // South inputs: last row from din_s, others from mesh_n of row below
    for (genvar c = 0; c < NUM_COLS; c++) begin : south_input_gen
        assign pe_din_s[NUM_ROWS-1][c] = din_s[c];
    end
    for (genvar r = 0; r < NUM_ROWS-1; r++) begin : south_input_gen_r
        for (genvar c = 0; c < NUM_COLS; c++) begin : south_input_gen_c
            assign pe_din_s[r][c] = mesh_n[r+1][c];
        end
    end

    // West inputs: col 0 from din_w, others from mesh_e of col-1 with boundary isolation
    for (genvar r = 0; r < NUM_ROWS; r++) begin : west_input_gen_r
        assign pe_din_w[r][0] = din_w[r];
    end
    for (genvar r = 0; r < NUM_ROWS; r++) begin : west_input_gen_r2
        for (genvar c = 1; c < NUM_COLS; c++) begin : west_input_gen_c
            assign pe_din_w[r][c] = (region_id_mask[c] != region_id_mask[c-1]) ? '0 : mesh_e[r][c-1];
        end
    end

    // East inputs: last col = 0, others from mesh_w of col+1 with boundary isolation
    for (genvar r = 0; r < NUM_ROWS; r++) begin : east_input_gen_r
        assign pe_din_e[r][NUM_COLS-1] = '0;
    end
    for (genvar r = 0; r < NUM_ROWS; r++) begin : east_input_gen_r2
        for (genvar c = 0; c < NUM_COLS-1; c++) begin : east_input_gen_c
            assign pe_din_e[r][c] = (region_id_mask[c] != region_id_mask[c+1]) ? '0 : mesh_w[r][c+1];
        end
    end

    // Instantiate PE array
    for (genvar r = 0; r < NUM_ROWS; r++) begin : row_gen
        for (genvar c = 0; c < NUM_COLS; c++) begin : col_gen
            hdf_pe #(
                .DATA_W(DATA_W),
                .ACC_W(ACC_W),
                .LIFETIME_W(LIFETIME_W),
                .REGION_W(REGION_W)
            ) pe_inst (
                .clk(clk),
                .rst_n(rst_n),
                .din_n(pe_din_n[r][c]),
                .din_s(pe_din_s[r][c]),
                .din_e(pe_din_e[r][c]),
                .din_w(pe_din_w[r][c]),
                .dout_n(pe_dout_n[r][c]),
                .dout_s(pe_dout_s[r][c]),
                .dout_e(pe_dout_e[r][c]),
                .dout_w(pe_dout_w[r][c]),
                .acc_out(pe_acc_out[r][c]),
                .dataflow_mode(dataflow_mode[c]),
                .region_id(region_id[c]),
                .region_reassign(region_reassign[c]),
                .route_sel(route_sel[c]),
                .w_ld(w_ld[c]),
                .acc_clr(acc_clr[c]),
                .lifetime_ld(lifetime_ld[c]),
                .lifetime_init(lifetime_init[c]),
                .bank_role_stale(pe_bank_role_stale[r][c]),
                .bank_role_clear(bank_role_clear[c])
            );

            // Connect outputs to mesh
            assign mesh_n[r][c] = pe_dout_n[r][c];
            assign mesh_s[r][c] = pe_dout_s[r][c];
            assign mesh_e[r][c] = pe_dout_e[r][c];
            assign mesh_w[r][c] = pe_dout_w[r][c];

            // Column outputs (from bottom row)
            if (r == NUM_ROWS-1) begin
                assign dout_n[c] = pe_dout_n[r][c];
                assign dout_s[c] = pe_dout_s[r][c];
                assign acc_out[c] = pe_acc_out[r][c];
                assign bank_role_stale[c] = pe_bank_role_stale[r][c];
            end

            // Row outputs (from rightmost column)
            if (c == NUM_COLS-1) begin
                assign dout_e[r] = pe_dout_e[r][c];
            end
        end
    end

endmodule