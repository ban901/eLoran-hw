// simple dual-port RAM: write (frame_rx) + registered read (correlator)
module seg_ram (
    input  wire        clk,
    input  wire        we,
    input  wire [10:0] waddr,
    input  wire [15:0] wdata,
    input  wire [10:0] raddr,
    output reg signed [15:0] rdata
);
    reg signed [15:0] mem [0:1829];
    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule
