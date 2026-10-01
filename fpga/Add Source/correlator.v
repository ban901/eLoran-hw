// ============================================================================
//  correlator.v  -  eLoran pulse correlation core
//  corr[k][c] = sum_{n=0..299} TPL[n] * seg[k*305 + c + n]   (c = 0,1,2)
//  6 pulses x 3 candidates = 18 results, each signed 64-bit, little-endian.
//  Throughput ~1 MAC/cycle (2-stage pipeline: mem read -> multiply -> acc).
//  @100 MHz : ~18*(300+3) = 5454 cycles = ~54.5 us.
// ============================================================================
module correlator #(
    parameter NTAP  = 300,
    parameter NPULSE= 6,
    parameter NCAND = 3,
    parameter SEG_STRIDE = 305
)(
    input  wire        clk,
    input  wire        rst,          // active-high, synchronous

    input  wire        start,        // 1-cycle (or level) trigger
    output reg         busy,
    output reg         done,         // stays high until next start

    // seg memory read port (registered, 1-cycle latency)
    output wire [10:0] seg_addr,
    input  wire signed [15:0] seg_data,

    // 18 x int64 results, byte b = result_flat[b*8 +: 8], LE per value
    output reg  [18*64-1:0] result_flat
);
    localparam NPAIR = NPULSE*NCAND; // 18

    // ---- counters ----
    reg [8:0]  n;         // tap index 0..NTAP (issue)
    reg [2:0]  k;         // pulse 0..5
    reg [1:0]  c;         // candidate 0..2
    reg [4:0]  pair;      // 0..17
    reg [10:0] kbase;     // k*305
    reg [8:0]  pcnt;      // products accumulated 0..NTAP
    reg signed [63:0] acc;

    // ---- address (combinational from n) ----
    wire issue = busy && (n < NTAP);
    assign seg_addr = kbase + {9'b0, c} + n;
    wire [8:0] tpl_a = n[8:0];

    // ---- template ROM (registered output, 1-cycle) ----
    wire signed [15:0] tpl_data;
    tpl_rom u_tpl (.clk(clk), .addr(tpl_a), .data(tpl_data));

    // ---- pipeline valids ----
    reg dv, pv;                    // data-valid, product-valid
    reg signed [31:0] product;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            busy<=1'b0; done<=1'b0; n<=NTAP; k<=0; c<=0; pair<=0;
            kbase<=0; pcnt<=0; acc<=0; dv<=0; pv<=0; product<=0;
            result_flat<=0;
        end else begin
            // ---- pipeline advance ----
            dv <= issue;                 // data valid one cycle after issue
            pv <= dv;                    // product valid one cycle after data
            if (dv) product <= seg_data * tpl_data;   // signed*signed
            if (pv) begin
                acc  <= acc + {{32{product[31]}}, product};
                pcnt <= pcnt + 1'b1;
            end
            // ---- advance issue counter ----
            if (issue) n <= n + 1'b1;

            // ---- start ----
            if (start && !busy) begin
                busy    <= 1'b1;
                done    <= 1'b0;
                n       <= 0;
                k       <= 0;
                c       <= 0;
                pair    <= 0;
                kbase   <= 0;
                acc     <= 0;
                pcnt    <= 0;
                dv      <= 0;
                pv      <= 0;
            end
            // ---- pair complete (all NTAP products accumulated) ----
            else if (busy && pv && (pcnt == NTAP-1)) begin
                // this cycle performs the final accumulation for the pair;
                // acc (post-update) is the result -> capture via next value
                result_flat[pair*64 +: 64] <= acc + {{32{product[31]}}, product};
                if (pair == NPAIR-1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    pair <= pair + 1'b1;
                    // next (k,c)
                    if (c == NCAND-1) begin
                        c       <= 0;
                        k       <= k + 1'b1;
                        kbase   <= kbase + SEG_STRIDE;
                    end else  c <= c + 1'b1;
                    // restart tap pipeline for next pair
                    n       <= 0;
                    acc     <= 0;
                    pcnt    <= 0;
                    dv      <= 0; 
                    pv      <= 0;
                    product <= 0;
                end
            end
        end
    end
endmodule
