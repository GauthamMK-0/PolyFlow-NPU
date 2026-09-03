// hdf_fission_decoder.v — Dynamic Column Partitioning Decoder for DRDS-NPU / HDF-NPU
// Partitions PE array into independent regions at dispatch time.

`timescale 1ns/1ps

module hdf_fission_decoder #(
    parameter int NUM_COLS = 4
) (
    input  logic                 clk,
    input  logic                 rst_n,

    // Dispatch configuration
    input  logic [3:0]           cfg_split_col,
    input  logic                 cfg_update_strobe,

    // Generated masks
    output logic [NUM_COLS-1:0]  region_id_mask,
    output logic [NUM_COLS-1:0]  region_reassign_bus
);

    logic [NUM_COLS-1:0] new_mask;

    always_comb begin
        for (int c = 0; c < NUM_COLS; c++) begin
            new_mask[c] = (c >= cfg_split_col);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Default: symmetric split
            region_id_mask      <= '0;
            region_reassign_bus <= '0;
            for (int c = 0; c < NUM_COLS; c++) begin
                if (c >= NUM_COLS/2) begin
                    region_id_mask[c] <= 1'b1;
                end
            end
        end else if (cfg_update_strobe) begin
            region_reassign_bus <= region_id_mask ^ new_mask;
            region_id_mask      <= new_mask;
        end else begin
            region_reassign_bus <= '0;
        end
    end

endmodule
