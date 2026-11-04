// hdf_pe.sv — Heterogeneous Processing Element for PolyFlow-NPU (Non-Pipelined Variant)
// Supports runtime WS / OS / IS switching, lifetime drain counter, and bank stale handshakes.
// 32-bit vertical partial-sum mesh.

`timescale 1ns/1ps

module hdf_pe #(
    parameter int DATA_W     = 8,
    parameter int ACC_W      = 32,
    parameter int LIFETIME_W = 8
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Directional streaming data ports
    input  logic [ACC_W-1:0]        din_n, // Streams North -> South (32 bits)
    input  logic [DATA_W-1:0]       din_w, // Streams West -> East (8 bits)
    output logic [ACC_W-1:0]        dout_s,
    output logic [DATA_W-1:0]       dout_e,

    // Full accumulator output
    output logic [ACC_W-1:0]        acc_out,

    // Runtime dataflow & region configuration
    input  logic [1:0]              dataflow_mode, // 00=WS, 01=OS, 10=IS, 11=RSVD
    input  logic                    region_reassign,

    // Lifetime counter (drain window during handover)
    input  logic                    lifetime_ld,
    input  logic [LIFETIME_W-1:0]   lifetime_init,

    // Bank safety handshake
    output logic                    bank_role_stale,
    input  logic                    bank_role_clear,

    // Execution control
    input  logic                    w_ld,          // Preload stationary operand
    input  logic                    acc_clr        // Clear accumulator
);

    typedef enum logic [1:0] {
        DF_WS  = 2'b00,
        DF_OS  = 2'b01,
        DF_IS  = 2'b10,
        DF_RSV = 2'b11
    } dataflow_e;

    logic [DATA_W-1:0]     stat_operand_reg;
    logic [LIFETIME_W-1:0] lifetime_cnt;
    wire                   lifetime_active = (lifetime_cnt != '0) || lifetime_ld;
    wire                   mac_en = lifetime_active && !bank_role_stale;

    // Lifetime counter countdown
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lifetime_cnt <= '0;
        end else if (lifetime_ld) begin
            lifetime_cnt <= lifetime_init;
        end else if (lifetime_cnt != '0) begin
            lifetime_cnt <= lifetime_cnt - 1'b1;
        end
    end

    // Bank role stale handshake
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bank_role_stale <= 1'b0;
        end else if (region_reassign) begin
            bank_role_stale <= 1'b1;
        end else if (bank_role_clear) begin
            bank_role_stale <= 1'b0;
        end
    end

    // Stationary operand preload register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stat_operand_reg <= '0;
        end else if (w_ld && !bank_role_stale) begin
            stat_operand_reg <= (dataflow_mode == DF_WS) ? din_w : din_n[DATA_W-1:0];
        end
    end

    // Operand selection and isolation
    wire signed [DATA_W-1:0] mul_a = (dataflow_mode == DF_OS) ? $signed(din_n[DATA_W-1:0]) : $signed(stat_operand_reg);
    wire signed [DATA_W-1:0] mul_b = $signed(din_w);
    logic signed [2*DATA_W-1:0] product;
    logic signed [ACC_W-1:0]    product_sext;

    assign product      = mul_a * mul_b;
    assign product_sext = {{ (ACC_W - 2*DATA_W){product[2*DATA_W-1]} }, product};

    wire compute_active  = mac_en;
    wire _unused_acc = &{1'b0, acc_clr};

    wire signed [ACC_W-1:0] psum_comb = $signed(din_n) + product_sext;

    // Forward passing
    assign dout_e  = (w_ld && (dataflow_mode == DF_WS) && !bank_role_stale) ? stat_operand_reg : din_w;
    assign dout_s  = (w_ld && (dataflow_mode == DF_IS) && !bank_role_stale) ? {{ (ACC_W-DATA_W){1'b0} }, stat_operand_reg} :
                     (dataflow_mode == DF_OS) ? din_n : psum_comb;

    assign acc_out = compute_active ? ((dataflow_mode == DF_OS || dataflow_mode == DF_IS) ? product_sext : psum_comb) : '0;

endmodule
