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

    // --- Stage 1: Operand Selection & Multiplication (with Pipeline Register) ---
    wire signed [DATA_W-1:0] mul_a = (dataflow_mode == DF_OS) ? $signed(din_n) : $signed(stat_operand_reg);
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
            compute_pipe <= compute_en;
        end
    end

    wire signed [ACC_W-1:0] product_sext = {{ (ACC_W - 2*DATA_W){product_reg[2*DATA_W-1]} }, product_reg};

    // --- Stage 2: Redundant Carry-Save Accumulator (CSA) ---
    logic [ACC_W-1:0] acc_sum;
    logic [ACC_W-1:0] acc_carry;

    wire [ACC_W-1:0] next_csa_sum;
    wire [ACC_W-1:0] next_csa_carry;

    genvar i;
    generate
        for (i = 0; i < ACC_W; i++) begin : gen_csa
            wire a_bit = acc_sum[i];
            wire b_bit = acc_carry[i];
            wire c_bit = product_sext[i];

            assign next_csa_sum[i] = a_bit ^ b_bit ^ c_bit;
            if (i < ACC_W-1) begin : gen_csa_carry
                assign next_csa_carry[i+1] = (a_bit & b_bit) | (b_bit & c_bit) | (a_bit & c_bit);
            end
        end
    endgenerate
    assign next_csa_carry[0] = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_sum   <= '0;
            acc_carry <= '0;
        end else if (acc_clr) begin
            acc_sum   <= '0;
            acc_carry <= '0;
        end else if (compute_pipe) begin
            acc_sum   <= next_csa_sum;
            acc_carry <= next_csa_carry;
        end
    end

    // Systolic forward passing (N -> S, W -> E)
    assign dout_s  = din_n;
    assign dout_e  = din_w;

    // Resolved accumulator output
    assign acc_out = acc_sum + acc_carry;

endmodule
