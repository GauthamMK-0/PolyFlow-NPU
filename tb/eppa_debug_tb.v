module eppa_arbiter_debug_tb;

    localparam int NUM_REGIONS = 2;
    localparam int BW_W        = 8;

    logic clk;
    logic rst_n;
    logic [2*NUM_REGIONS-1:0] phase_tag;
    logic [NUM_REGIONS*BW_W-1:0] bw_alloc;
    logic [NUM_REGIONS-1:0] reconfig_urgent;

    eppa_arbiter #(
        .NUM_REGIONS(NUM_REGIONS),
        .BW_W(BW_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .phase_tag(phase_tag),
        .bw_alloc(bw_alloc),
        .reconfig_urgent(reconfig_urgent)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("/root/research/mt_npu/tb/eppa_debug.vcd");
        $dumpvars(0, eppa_arbiter_debug_tb);

        rst_n = 0;
        phase_tag = 4'b0000;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        
        $display("After reset: phase_tag=%b, bw_alloc=%h, phase_tag_prev=%b", phase_tag, bw_alloc, dut.phase_tag_prev);
        
        phase_tag = 4'b0000; // Both BURST
        @(negedge clk);
        $display("Before posedge: phase_tag=%b", phase_tag);
        @(posedge clk);
        $display("After posedge: phase_tag=%b, bw_alloc=%h, phase_tag_prev=%b", phase_tag, bw_alloc, dut.phase_tag_prev);
        
        phase_tag = 4'b0000; // Same
        @(negedge clk);
        @(posedge clk);
        $display("Same BURST: phase_tag=%b, bw_alloc=%h, phase_tag_prev=%b", phase_tag, bw_alloc, dut.phase_tag_prev);
        
        $finish;
    end

endmodule