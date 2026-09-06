// hdf_pe.sv — Heterogeneous Processing Element for PolyFlow-NPU
// Supports runtime WS / OS / IS switching, lifetime drain counter, and bank stale handshakes.

`timescale 1ns/1ps

module hdf_pe #(
    parameter int DATA_W     = 8,
    parameter int ACC_W      = 32,
    parameter int LIFETIME_W = 4,
    parameter int REGION_W   = 1
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Directional streaming data ports
    input  logic [DATA_W-1:0]       din_n, // Streams North -> South
    input  logic [DATA_W-1:0]       din_w, // Streams West -> East
    output logic [DATA_W-1:0]       dout_s,
    output logic [DATA_W-1:0]       dout_e,

    // Full accumulator output
    output logic [ACC_W-1:0]        acc_out,

    // Runtime dataflow & region configuration
    input  logic [1:0]              dataflow_mode, // 00=WS, 01=OS, 10=IS, 11=RSVD
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [REGION_W-1:0]     region_id,
    /* verilator lint_on UNUSEDSIGNAL */
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
    logic [ACC_W-1:0]      mac_acc;
    logic [LIFETIME_W-1:0] lifetime_cnt;
    wire                   lifetime_active = (lifetime_cnt != '0);
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
            stat_operand_reg <= (dataflow_mode == DF_WS) ? din_w : din_n;
        end
    end

    // Multiplier operand assignment per dataflow mode
    logic signed [DATA_W-1:0]   mul_a, mul_b;
    logic signed [2*DATA_W-1:0] product;
    logic signed [ACC_W-1:0]    product_sext;

    always_comb begin
        case (dataflow_mode)
            DF_WS: begin
                // WS: Weight is stationary; Activation streams from West
                mul_a = $signed(stat_operand_reg);
                mul_b = $signed(din_w);
            end
            DF_OS: begin
                // OS: Q streams from North; K streams from West
                mul_a = $signed(din_n);
                mul_b = $signed(din_w);
            end
            DF_IS: begin
                // IS: Activation is stationary; Weight streams from West
                mul_a = $signed(stat_operand_reg);
                mul_b = $signed(din_w);
            end
            default: begin
                mul_a = '0;
                mul_b = '0;
            end
        endcase
    end

    assign product      = mul_a * mul_b;
    assign product_sext = {{ (ACC_W - 2*DATA_W){product[2*DATA_W-1]} }, product};

    // MAC Accumulation register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_acc <= '0;
        end else if (acc_clr) begin
            mac_acc <= '0;
        end else if (mac_en) begin
            mac_acc <= mac_acc + product_sext;
        end
    end

    // Systolic forward passing
    assign dout_s  = din_n;
    assign dout_e  = din_w;
    assign acc_out = mac_acc;

endmodule
