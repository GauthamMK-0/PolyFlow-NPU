// pod_bank_scrub.v — 4-Cycle Mandatory Zeroing Scrub Controller for PolyFlow-NPU
// Zeroes residual operand data during bank role transitions before emitting bank_role_clear.

`timescale 1ns/1ps

module pod_bank_scrub #(
    parameter int REGION_W  = 1,
    parameter int SCRUB_CYC = 4
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 role_reassign,
    input  logic [REGION_W-1:0]  new_region_id,
    input  logic [1:0]           new_role,
    output logic                 scrub_active,
    output logic                 bank_role_clear,
    output logic [REGION_W-1:0]  region_owner,
    output logic [1:0]           role_tag
);

    localparam int CNT_W = $clog2(SCRUB_CYC + 1);
    logic [CNT_W-1:0]    scrub_cnt;
    logic [REGION_W-1:0] latched_region_id;
    logic [1:0]          latched_role;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scrub_active      <= 1'b0;
            bank_role_clear   <= 1'b0;
            scrub_cnt         <= '0;
            region_owner      <= '0;
            role_tag          <= 2'b11; // 2'b11 = Idle / Scrubbing
            latched_region_id <= '0;
            latched_role      <= 2'b00;
        end else begin
            bank_role_clear <= 1'b0;

            if (role_reassign && !scrub_active) begin
                scrub_active      <= 1'b1;
                scrub_cnt         <= SCRUB_CYC[CNT_W-1:0];
                latched_region_id <= new_region_id;
                latched_role      <= new_role;
            end else if (scrub_active) begin
                scrub_cnt <= scrub_cnt - 1'b1;
                if (scrub_cnt == 1) begin
                    scrub_active    <= 1'b0;
                    bank_role_clear <= 1'b1;
                    region_owner    <= latched_region_id;
                    role_tag        <= latched_role;
                end
            end
        end
    end

endmodule
