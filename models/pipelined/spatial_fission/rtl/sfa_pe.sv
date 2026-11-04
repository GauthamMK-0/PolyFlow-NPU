// sfa_pe.sv — Processing Element for Homogeneous Spatial Fission Model
// Pinned to Weight-Stationary (WS) dataflow (Planaria-style architecture).
// 32-bit vertical partial-sum mesh + registered systolic forward hops.

`timescale 1ns/1ps

module sfa_pe #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Directional streaming data ports
    // din_n / dout_s carry 32-bit partial sums down columns
    input  logic [ACC_W-1:0]        din_n, // Streams North -> South (32 bits)
    input  logic [DATA_W-1:0]       din_w, // Streams West -> East (8 bits)
    output logic [ACC_W-1:0]        dout_s,
    output logic [DATA_W-1:0]       dout_e,

    // Full precision accumulator output
    output logic [ACC_W-1:0]        acc_out,

    // Region assignment & security flags
    input  logic                    region_reassign,
    output logic                    bank_role_stale,
    input  logic                    bank_role_clear,

    // Control signals
    input  logic                    w_ld,          // Preload stationary weight
    input  logic                    acc_clr,       // Clear accumulator
    input  logic                    compute_en     // Compute enable
);

    logic [DATA_W-1:0] stat_weight;

    // Bank role stale handshake (protects against reading stale un-scrubbed memory)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bank_role_stale <= 1'b0;
        end else if (region_reassign) begin
            bank_role_stale <= 1'b1;
        end else if (bank_role_clear) begin
            bank_role_stale <= 1'b0;
        end
    end

    // Weight stationary preload register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stat_weight <= '0;
        end else if (w_ld && !bank_role_stale) begin
            stat_weight <= din_w;
        end
    end

    // --- Stage 1: Multiplication with Pipeline Register ---
    wire compute_active = compute_en && !bank_role_stale;
    wire signed [DATA_W-1:0] mul_a = $signed(stat_weight);
    wire signed [DATA_W-1:0] mul_b = $signed(din_w);

    logic signed [2*DATA_W-1:0] product_raw;
    logic signed [2*DATA_W-1:0] product_reg;
    logic                       compute_pipe;

    assign product_raw = mul_a * mul_b;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_reg  <= '0;
            compute_pipe <= 1'b0;
        end else if (acc_clr) begin
            product_reg  <= '0;
            compute_pipe <= 1'b0;
        end else begin
            product_reg  <= product_raw;
            compute_pipe <= compute_active;
        end
    end

    wire signed [ACC_W-1:0] product_sext = {{ (ACC_W - 2*DATA_W){product_reg[2*DATA_W-1]} }, product_reg};

    // --- Stage 2: Partial Sum Addition ---
    wire signed [ACC_W-1:0] psum_next = $signed(din_n) + product_sext;
    logic [ACC_W-1:0]       acc_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_reg <= '0;
        end else if (acc_clr) begin
            acc_reg <= '0;
        end else if (compute_pipe) begin
            acc_reg <= psum_next;
        end
    end

    // --- Registered Systolic Inter-PE Forwarding ---
    logic [DATA_W-1:0] din_w_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            din_w_reg <= '0;
            dout_s    <= '0;
        end else begin
            din_w_reg <= din_w;
            // Vertical 32-bit partial sum forwarded South
            dout_s    <= psum_next;
        end
    end

    // Horizontal shift during preload, activation forward during compute
    assign dout_e = (w_ld && !bank_role_stale) ? stat_weight : din_w_reg;

    // Resolved accumulator output
    assign acc_out = acc_reg;

endmodule
