// dfs_pe.sv — Processing Element for Single-Tenant Dataflow Switching
// Supports runtime switching across Weight-Stationary (WS), Output-Stationary (OS), and Input-Stationary (IS).

`timescale 1ns/1ps

module dfs_pe #(
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

    // Runtime configuration & control
    input  logic [1:0]              dataflow_mode, // 00=WS, 01=OS, 10=IS, 11=RSVD
    input  logic                    w_ld,          // Preload stationary operand
    input  logic                    acc_clr,       // Clear accumulator
    input  logic                    compute_en     // Gate computation
);

    typedef enum logic [1:0] {
        DF_WS  = 2'b00,
        DF_OS  = 2'b01,
        DF_IS  = 2'b10,
        DF_RSV = 2'b11
    } dataflow_e;

    logic [DATA_W-1:0] stat_operand_reg;
    logic [ACC_W-1:0]  mac_acc;

    // Stationary operand preload register
    // WS: preloads filter weight from West port
    // IS: preloads input activation from North port
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stat_operand_reg <= '0;
        end else if (w_ld) begin
            stat_operand_reg <= (dataflow_mode == DF_WS) ? din_w : din_n;
        end
    end

    // Operand selection and isolation
    wire signed [DATA_W-1:0] mul_a = (dataflow_mode == DF_OS) ? $signed(din_n) : $signed(stat_operand_reg);
    wire signed [DATA_W-1:0] mul_b = $signed(din_w);
    wire signed [DATA_W-1:0] mul_a_clamped = compute_en ? mul_a : '0;
    wire signed [DATA_W-1:0] mul_b_clamped = compute_en ? mul_b : '0;

    logic signed [2*DATA_W-1:0] product;
    logic signed [ACC_W-1:0]    product_sext;

    assign product      = mul_a_clamped * mul_b_clamped;
    assign product_sext = {{ (ACC_W - 2*DATA_W){product[2*DATA_W-1]} }, product};

    wire is_zero_operand = (mul_a == '0) || (mul_b == '0);
    wire do_accumulate   = compute_en && !is_zero_operand;

    // MAC Accumulation register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_acc <= '0;
        end else if (acc_clr) begin
            mac_acc <= '0;
        end else if (do_accumulate) begin
            mac_acc <= mac_acc + product_sext;
        end
    end

    // Systolic forward passing (N -> S, W -> E)
    assign dout_s  = din_n;
    assign dout_e  = din_w;
    assign acc_out = mac_acc;

endmodule
