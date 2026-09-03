module pod_fission_decoder #(
    parameter int NUM_COLS = 16
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic [3:0]           cfg_split_col,
    input  logic                 cfg_update_strobe,
    output logic [NUM_COLS-1:0]  region_id_mask,
    output logic [NUM_COLS-1:0]  region_reassign_bus
);

    logic [NUM_COLS-1:0] region_id_prev;
    logic [NUM_COLS-1:0] new_mask;

    // Combinational: compute new mask from cfg_split_col
    always_comb begin
        for (int c = 0; c < NUM_COLS; c++) begin
            new_mask[c] = (c >= cfg_split_col);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Default: split at NUM_COLS/2 (8 columns each)
            region_id_mask      <= '0;
            region_id_prev      <= '0;
            region_reassign_bus <= '0;
            for (int c = 0; c < NUM_COLS; c++) begin
                if (c >= NUM_COLS/2) begin
                    region_id_mask[c]  <= 1'b1;
                    region_id_prev[c]  <= 1'b1;
                end
            end
        end else if (cfg_update_strobe) begin
            region_id_prev      <= region_id_mask;
            region_id_mask      <= new_mask;
            region_reassign_bus <= region_id_mask ^ new_mask; // Compare OLD mask with NEW mask
        end else begin
            region_reassign_bus <= '0;
        end
    end

endmodule