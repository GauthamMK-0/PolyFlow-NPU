module eppa_arbiter #(
    parameter int NUM_REGIONS = 2,
    parameter int BW_W        = 8
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [2*NUM_REGIONS-1:0] phase_tag,
    output logic [NUM_REGIONS*BW_W-1:0] bw_alloc,
    output logic [NUM_REGIONS-1:0]      reconfig_urgent
);

    typedef enum logic [1:0] {
        PH_BURST    = 2'b00,
        PH_IDLE     = 2'b01,
        PH_STREAM   = 2'b10,
        PH_RECONFIG = 2'b11
    } phase_e;

    logic [2*NUM_REGIONS-1:0] phase_tag_prev;
    logic                     any_transition;
    logic                     first_cycle;

    assign any_transition = (phase_tag != phase_tag_prev) || first_cycle;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_tag_prev  <= {NUM_REGIONS{2'b01}}; // Initialize to IDLE to detect first transition
            bw_alloc        <= '0;
            reconfig_urgent <= '0;
            first_cycle     <= 1'b1;
        end else begin
            phase_tag_prev <= phase_tag;
            first_cycle    <= 1'b0;

            if (any_transition) begin
                for (int i = 0; i < NUM_REGIONS; i++) begin
                    unique case (phase_tag[2*i +: 2])
                        PH_BURST: begin
                            bw_alloc[i*BW_W +: BW_W] <= {BW_W{1'b1}};
                            reconfig_urgent[i]        <= 1'b0;
                        end
                        PH_RECONFIG: begin
                            bw_alloc[i*BW_W +: BW_W] <= {BW_W{1'b1}};
                            reconfig_urgent[i]        <= 1'b1;
                        end
                        PH_STREAM: begin
                            bw_alloc[i*BW_W +: BW_W] <= {1'b0, {(BW_W-1){1'b1}}};
                            reconfig_urgent[i]        <= 1'b0;
                        end
                        default: begin // PH_IDLE
                            bw_alloc[i*BW_W +: BW_W] <= '0;
                            reconfig_urgent[i]        <= 1'b0;
                        end
                    endcase
                end
            end
        end
    end

endmodule