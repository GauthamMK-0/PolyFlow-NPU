module hdf_pe #(
    parameter int DATA_W      = 8,
    parameter int ACC_W       = 32,
    parameter int LIFETIME_W  = 4,
    parameter int REGION_W    = 1
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Mesh data ports
    input  logic [DATA_W-1:0]       din_n,
    input  logic [DATA_W-1:0]       din_s,
    input  logic [DATA_W-1:0]       din_e,
    input  logic [DATA_W-1:0]       din_w,
    output logic [DATA_W-1:0]       dout_n,
    output logic [DATA_W-1:0]       dout_s,
    output logic [DATA_W-1:0]       dout_e,
    output logic [DATA_W-1:0]       dout_w,

    // Full accumulator drain port (for column-wise collection)
    output logic [ACC_W-1:0]        acc_out,

    // Dataflow & region control
    input  logic [1:0]              dataflow_mode,
    input  logic [REGION_W-1:0]     region_id,
    input  logic                    region_reassign,
    input  logic [3:0]              route_sel,

    // Preload strobe (WS: west, IS: north)
    input  logic                    w_ld,

    // Accumulator clear at tile boundary
    input  logic                    acc_clr,

    // Lifetime counter (drain window on handover)
    input  logic                    lifetime_ld,
    input  logic [LIFETIME_W-1:0]   lifetime_init,

    // Bank ownership handshake
    output logic                    bank_role_stale,
    input  logic                    bank_role_clear
);

    typedef enum logic [1:0] {
        DF_WS = 2'b00,
        DF_OS = 2'b01,
        DF_IS = 2'b10,
        DF_RSV = 2'b11
    } dataflow_e;

    logic [DATA_W-1:0]  stat_operand;
    logic [DATA_W-1:0]  stat_operand_reg;
    logic [DATA_W-1:0]  stream_operand;
    logic [ACC_W-1:0]   mac_acc;
    logic [LIFETIME_W-1:0] lifetime_cnt;
    logic               lifetime_active;
    logic               mac_en;

    logic [DATA_W-1:0]  op_in_n, op_in_s, op_in_e, op_in_w;

    assign op_in_n = route_sel[3] ? din_n : '0;
    assign op_in_s = route_sel[2] ? din_s : '0;
    assign op_in_e = route_sel[1] ? din_e : '0;
    assign op_in_w = route_sel[0] ? din_w : '0;

    assign lifetime_active = (lifetime_cnt != '0);
    assign mac_en = lifetime_active;

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

    // Bank role stale flag
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bank_role_stale <= 1'b0;
        end else if (region_reassign) begin
            bank_role_stale <= 1'b1;
        end else if (bank_role_clear) begin
            bank_role_stale <= 1'b0;
        end
    end

    // Stationary operand register (latched on w_ld for WS/IS preload)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stat_operand_reg <= '0;
        end else if (w_ld) begin
            stat_operand_reg <= (dataflow_mode == 2'b00) ? op_in_w : op_in_n; // WS: west, IS: north
        end
    end

    // Operand assignment per dataflow mode
    always_comb begin
        stat_operand   = '0;
        stream_operand = '0;
        unique case (dataflow_mode)
            DF_WS: begin // Weight-Stationary
                stat_operand   = stat_operand_reg; // latched weight
                stream_operand = op_in_e;          // activations stream eastbound
            end
            DF_OS: begin // Output-Stationary
                stat_operand   = '0;               // no stationary operand
                stream_operand = op_in_w;          // K from west
            end
            DF_IS: begin // Input-Stationary
                stat_operand   = stat_operand_reg; // latched input activation
                stream_operand = op_in_e;          // weights stream eastbound
            end
            default: begin // DF_RSV
                stat_operand   = '0;
                stream_operand = '0;
            end
        endcase
    end

    // MAC accumulator: acc += stat_operand * stream_operand (for WS/IS)
    // For OS: acc += op_in_n * op_in_w (Q * K)
    logic signed [DATA_W-1:0]   op_a, op_b;
    logic signed [2*DATA_W-1:0] product;

    always_comb begin
        unique case (dataflow_mode)
            DF_WS, DF_IS: begin
                op_a = $signed(stat_operand);
                op_b = $signed(stream_operand);
            end
            DF_OS: begin
                op_a = $signed(op_in_n);  // Q from north
                op_b = $signed(op_in_w);  // K from west
            end
            default: begin
                op_a = '0;
                op_b = '0;
            end
        endcase
    end

    assign product = op_a * op_b;

    // Sign-extend product to ACC_W bits
    logic signed [ACC_W-1:0] product_sext;
    assign product_sext = {{(ACC_W-2*DATA_W){product[2*DATA_W-1]}}, product};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_acc <= '0;
        end else if (acc_clr) begin
            mac_acc <= '0;
        end else if (mac_en) begin
            mac_acc <= mac_acc + product_sext;
        end
    end

    // Output routing
    // WS/IS: dout_e = pass-through stream operand (eastbound)
    //        dout_s = accumulator drain (southbound)
    // OS:    dout_s = pass-through Q (southbound during compute), acc_out on drain
    //        dout_e = pass-through K (eastbound)
    always_comb begin
        dout_n = op_in_s;  // default pass-through N<-S
        dout_s = op_in_n;  // default pass-through S<-N
        dout_e = op_in_w;  // default pass-through E<-W
        dout_w = op_in_e;  // default pass-through W<-E

        unique case (dataflow_mode)
            DF_WS: begin
                dout_e = stream_operand;          // pass activations east
                dout_s = mac_acc[DATA_W-1:0];     // drain partial sum south (truncated for mesh)
            end
            DF_IS: begin
                dout_e = stream_operand;          // pass weights east
                dout_s = mac_acc[DATA_W-1:0];     // drain partial sum south
            end
            DF_OS: begin
                dout_s = op_in_n;                 // pass Q south during compute
                dout_e = op_in_w;                 // pass K east
            end
            default: begin
                // reserved: all pass-through
            end
        endcase
    end

    // Full accumulator output for column collector
    assign acc_out = mac_acc;

endmodule