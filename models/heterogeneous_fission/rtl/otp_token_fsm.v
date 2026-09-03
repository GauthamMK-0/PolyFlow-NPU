// otp_token_fsm.v — Single-Writer Ownership Token Protocol for DRDS-NPU / HDF-NPU
// Decentralizes bank reconfiguration handshakes and guarantees mutual exclusion across regions.

`timescale 1ns/1ps

module otp_token_fsm #(
    parameter int NUM_REGIONS = 2,
    parameter int REGION_W    = 1,
    parameter int EPOCH_W     = 8
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [NUM_REGIONS-1:0]  token_req,
    input  logic [NUM_REGIONS-1:0]  token_release,
    input  logic                    scrub_active,
    output logic [REGION_W-1:0]     token_owner,
    output logic                    token_held,
    output logic [NUM_REGIONS-1:0]  grant
);

    typedef enum logic [1:0] {
        S_FREE  = 2'b00,
        S_OWNED = 2'b01,
        S_SCRUB = 2'b10
    } state_e;

    state_e state, next_state;
    logic [REGION_W-1:0] priority_base;
    logic [EPOCH_W-1:0]  epoch_cnt;
    logic [REGION_W-1:0] candidate;
    logic                found;
    logic                grant_pulse;

    // Epoch counter for rotating priority
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            epoch_cnt     <= '0;
            priority_base <= '0;
        end else if (epoch_cnt == {EPOCH_W{1'b1}}) begin
            epoch_cnt     <= '0;
            priority_base <= priority_base + 1'b1;
        end else begin
            epoch_cnt <= epoch_cnt + 1'b1;
        end
    end

    // Rotating priority encoder
    always_comb begin
        found     = 1'b0;
        candidate = '0;
        for (int k = 0; k < NUM_REGIONS; k++) begin
            logic [REGION_W-1:0] idx;
            idx = (priority_base + k[REGION_W-1:0]) % NUM_REGIONS;
            if (!found && token_req[idx]) begin
                candidate = idx;
                found     = 1'b1;
            end
        end
    end

    assign grant_pulse = (state == S_FREE || state == S_SCRUB) && (next_state == S_OWNED) && found;

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            S_FREE: begin
                if (found) begin
                    next_state = S_OWNED;
                end
            end
            S_OWNED: begin
                if (scrub_active) begin
                    next_state = S_SCRUB;
                end else if (token_release[token_owner]) begin
                    next_state = S_FREE;
                end
            end
            S_SCRUB: begin
                if (!scrub_active) begin
                    if (found) begin
                        next_state = S_OWNED;
                    end else begin
                        next_state = S_FREE;
                    end
                end
            end
            default: next_state = S_FREE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_FREE;
        else        state <= next_state;
    end

    // Token ownership tracking
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            token_owner <= '0;
            token_held  <= 1'b0;
            grant       <= '0;
        end else begin
            grant <= grant_pulse ? (1'b1 << candidate) : '0;

            case (next_state)
                S_FREE: begin
                    token_held <= 1'b0;
                end
                S_OWNED: begin
                    if (state == S_FREE || state == S_SCRUB) begin
                        token_owner <= candidate;
                        token_held  <= 1'b1;
                    end else if (token_release[token_owner]) begin
                        token_held  <= 1'b0;
                    end
                end
                S_SCRUB: begin
                    token_held <= 1'b0;
                end
                default: ;
            endcase
        end
    end

endmodule
