// dfs_pe.sv — Processing Element for Single-Tenant Dataflow Switching (Non-Pipelined Variant)
// Supports runtime switching across Weight-Stationary (WS), Output-Stationary (OS), and Input-Stationary (IS).
// 32-bit vertical partial-sum mesh.

`timescale 1ns/1ps

module dfs_pe #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Directional streaming data ports
    input  logic [ACC_W-1:0]        din_n, // Streams North -> South (32 bits)
    input  logic [DATA_W-1:0]       din_w, // Streams West -> East (8 bits)
    output logic [ACC_W-1:0]        dout_s,
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

    // Stationary operand preload register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stat_operand_reg <= '0;
        end else if (w_ld) begin
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

    wire do_accumulate   = compute_en;
    wire _unused_acc = &{1'b0, acc_clr};

    wire signed [ACC_W-1:0] psum_comb = $signed(din_n) + product_sext;

    // Forward passing
    assign dout_e  = (w_ld && (dataflow_mode == DF_WS)) ? stat_operand_reg : din_w;
    assign dout_s  = (w_ld && (dataflow_mode == DF_IS)) ? {{ (ACC_W-DATA_W){1'b0} }, stat_operand_reg} :
                     (dataflow_mode == DF_OS) ? din_n : psum_comb;

    assign acc_out = do_accumulate ? ((dataflow_mode == DF_OS || dataflow_mode == DF_IS) ? product_sext : psum_comb) : '0;

endmodule
