// ============================================================================
//  uart_rx.v - 8N1 UART receiver
//  CLKS_PER_BIT = f_clk / baud.  100 MHz / 460800 = 217.
// ============================================================================
module uart_rx #(
    parameter integer CLKS_PER_BIT = 217
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,          // async serial in (idle high)
    output reg        valid,       // 1-cycle strobe when byte ready
    output reg  [7:0] data
);
    localparam S_IDLE=0, S_START=1, S_DATA=2, S_STOP=3;
    reg [1:0]  state = S_IDLE;
    reg [15:0] cnt   = 0;
    reg [2:0]  bidx  = 0;
    reg        rx_q1=1'b1, rx_q2=1'b1;   // double-flop synchronizer

    always @(posedge clk) begin
        rx_q1 <= rx; rx_q2 <= rx_q1;
        valid <= 1'b0;
        if (rst) begin
            state<=S_IDLE; cnt<=0; bidx<=0;
        end else case (state)
            S_IDLE:  if (!rx_q2) begin state<=S_START; cnt<=0; end   // start bit
            S_START: if (cnt == CLKS_PER_BIT/2) begin
                        if (!rx_q2) begin cnt<=0; bidx<=0; state<=S_DATA; end
                        else          state<=S_IDLE;                 // false start
                     end else cnt<=cnt+1'b1;
            S_DATA:  if (cnt == CLKS_PER_BIT-1) begin
                        cnt<=0; data[bidx]<=rx_q2;
                        if (bidx==3'd7) state<=S_STOP; else bidx<=bidx+1'b1;
                     end else cnt<=cnt+1'b1;
            S_STOP:  if (cnt == CLKS_PER_BIT-1) begin
                        cnt<=0; valid<=1'b1; state<=S_IDLE;          // sample stop, emit
                     end else cnt<=cnt+1'b1;
        endcase
    end
endmodule
