// sfa_pe.sv — Processing Element for Homogeneous Spatial Fission Model
// Pinned to Weight-Stationary (WS) dataflow (Planaria-style architecture).

`timescale 1ns/1ps

module sfa_pe #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Directional streaming data ports
    input  logic [DATA_W-1:0]       din_n, // Streams North -> South
    input  logic [DATA_W-1:0]       din_w, // Streams West -> East
    output logic [DATA_W-1:0]       dout_s,
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
    logic [ACC_W-1:0]  mac_acc;

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

    // Operand isolation and zero detection
    wire compute_active = compute_en && !bank_role_stale;
    wire signed [DATA_W-1:0] mul_a = $signed(stat_weight);
    wire signed [DATA_W-1:0] mul_b = $signed(din_w);
    wire signed [DATA_W-1:0] mul_a_clamped = compute_active ? mul_a : '0;
    wire signed [DATA_W-1:0] mul_b_clamped = compute_active ? mul_b : '0;

    logic signed [2*DATA_W-1:0] product;
    logic signed [ACC_W-1:0]    product_sext;

    assign product      = mul_a_clamped * mul_b_clamped;
    assign product_sext = {{ (ACC_W - 2*DATA_W){product[2*DATA_W-1]} }, product};

    wire is_zero_operand = (mul_a == '0) || (mul_b == '0);
    wire do_accumulate   = compute_active && !is_zero_operand;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_acc <= '0;
        end else if (acc_clr) begin
            mac_acc <= '0;
        end else if (do_accumulate) begin
            mac_acc <= mac_acc + product_sext;
        end
    end

    // Systolic forward passing
    assign dout_s  = din_n;
    assign dout_e  = din_w;
    assign acc_out = mac_acc;

endmodule
