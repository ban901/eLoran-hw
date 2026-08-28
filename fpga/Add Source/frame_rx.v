// ============================================================================
//  frame_rx.v - parse [SOF 0xA5 0xC3][TYPE][PAYLOAD][CRC16] and store samples
//  TYPE 0x04 (CMD_LOAD): PAYLOAD = 3660 B = 1830 int16 (LE, pulse-major).
//  CRC-16/CCITT-FALSE over TYPE+PAYLOAD, transmitted hi-byte first.
//  (CRC coverage / byte order must match the PC MATLAB sender.)
// ============================================================================
module frame_rx (
    input  wire        clk,
    input  wire        rst,
    input  wire        b_valid,     // byte strobe from uart_rx
    input  wire [7:0]  b_data,

    // write port to seg RAM
    output reg         seg_we,
    output reg  [10:0] seg_waddr,
    output reg  [15:0] seg_wdata,

    output reg         loaded,      // 1-cycle pulse: full valid frame stored
    output reg         crc_ok,      // latched result of last frame's CRC
    output reg         busy_rx      // high while receiving a frame
);
    localparam TYPE_LOAD = 8'h04;
    localparam PAY_BYTES = 3660;

    localparam S_SOF1=0,S_SOF2=1,S_TYPE=2,S_PAY=3,S_CRC1=4,S_CRC2=5;
    reg [2:0]  st;
    reg [12:0] bcnt;          // payload byte counter 0..3659
    reg [10:0] sidx;          // sample index 0..1829
    reg        low_lat;       // have low byte latched
    reg [7:0]  low_byte;
    reg [15:0] crc;
    reg [7:0]  crc_lo;

    // CRC-16/CCITT-FALSE single-byte update (MSB first)
    function [15:0] crc_upd;
        input [15:0] c; input [7:0] d;
        integer i; reg [15:0] x;
        begin
            x = c ^ {d,8'h00};
            for (i=0;i<8;i=i+1)
                x = x[15] ? ((x<<1)^16'h1021) : (x<<1);
            crc_upd = x;
        end
    endfunction

    always @(posedge clk) begin
        seg_we <= 1'b0;
        loaded <= 1'b0;
        if (rst) begin
            st<=S_SOF1; bcnt<=0; sidx<=0; low_lat<=0; busy_rx<=0; crc_ok<=0;
        end else if (b_valid) begin
            case (st)
                S_SOF1: begin busy_rx<=0;
                    if (b_data==8'hA5) begin st<=S_SOF2; busy_rx<=1; end
                end
                S_SOF2: begin
                    if (b_data==8'hC3) st<=S_TYPE;
                    else if (b_data==8'hA5) st<=S_SOF2;
                    else begin st<=S_SOF1; busy_rx<=0; end
                end
                S_TYPE: begin
                    crc <= crc_upd(16'hFFFF, b_data);
                    if (b_data==TYPE_LOAD) begin
                        st<=S_PAY; bcnt<=0; sidx<=0; low_lat<=0;
                    end else begin st<=S_SOF1; busy_rx<=0; end
                end
                S_PAY: begin
                    crc <= crc_upd(crc, b_data);
                    if (!low_lat) begin
                        low_byte <= b_data; low_lat <= 1'b1;
                    end else begin
                        seg_wdata <= {b_data, low_byte};  // LE: first=low
                        seg_waddr <= sidx;
                        seg_we    <= 1'b1;
                        sidx      <= sidx + 1'b1;
                        low_lat   <= 1'b0;
                    end
                    if (bcnt==PAY_BYTES-1) st<=S_CRC1;
                    else bcnt<=bcnt+1'b1;
                end
                S_CRC1: begin crc_lo <= b_data; st<=S_CRC2; end   // LE: lo byte first
                S_CRC2: begin
                    crc_ok <= ({b_data,crc_lo}==crc);             // {hi,lo}
                    loaded <= 1'b1;          // frame complete (crc_ok tells validity)
                    busy_rx<= 1'b0;
                    st<=S_SOF1;
                end
            endcase
        end
    end
endmodule
