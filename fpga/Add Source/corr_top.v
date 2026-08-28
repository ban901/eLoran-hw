// ============================================================================
//  corr_top.v - eLoran correlation front-end (Basys3 / Artix-7)
//
//  Flow:  PC --UART 460800--> [frame_rx -> seg_ram]
//         MCU raises corr_start --> [correlator 18x300 MAC]
//         correlator raises corr_done --> MCU reads 144 B via [spi_slave]
//
//  Control uses GPIO (corr_start / corr_done); SPI is read-only.
// ============================================================================
module corr_top #(
    parameter integer CLKS_PER_BIT = 217   // 100 MHz / 460800
)(
    input  wire clk,           // W5, 100 MHz
    input  wire rst_btn,       // U18 (btnC), active-high

    input  wire uart_rx,       // B18 (RsRx) from PC

    // Pmod SPI (to MCU)
    input  wire spi_sck,
    input  wire spi_cs_n,
    input  wire spi_mosi,
    output wire spi_miso,

    // Pmod control (to/from MCU GPIO)
    input  wire corr_start,    // MCU -> FPGA : rising edge starts correlation
    output wire corr_done,     // FPGA -> MCU : high when results ready

    output wire [3:0] led       // 0:loaded 1:crc_ok 2:busy 3:done
);
    wire rst = rst_btn;

    // ---- UART -> frame parser -> seg RAM ----
    wire       b_valid; wire [7:0] b_data;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart
        (.clk(clk), .rst(rst), .rx(uart_rx), .valid(b_valid), .data(b_data));

    wire        seg_we;  wire [10:0] seg_waddr; wire [15:0] seg_wdata;
    wire        loaded, crc_ok, busy_rx;
    frame_rx u_frame
        (.clk(clk), .rst(rst), .b_valid(b_valid), .b_data(b_data),
         .seg_we(seg_we), .seg_waddr(seg_waddr), .seg_wdata(seg_wdata),
         .loaded(loaded), .crc_ok(crc_ok), .busy_rx(busy_rx));

    reg loaded_l;
    always @(posedge clk) if (rst) loaded_l<=0; else if (loaded) loaded_l<=1'b1;

    wire [10:0] seg_raddr; wire signed [15:0] seg_rdata;
    seg_ram u_seg
        (.clk(clk), .we(seg_we), .waddr(seg_waddr), .wdata(seg_wdata),
         .raddr(seg_raddr), .rdata(seg_rdata));

    // ---- start-trigger : synchronize + rising-edge detect ----
    reg [2:0] st_q;
    always @(posedge clk) st_q <= rst ? 3'b0 : {st_q[1:0], corr_start};
    wire start_pulse = (st_q[2:1]==2'b01);

    // ---- correlator ----
    wire busy, done;
    wire [18*64-1:0] result_flat;
    correlator u_corr
        (.clk(clk), .rst(rst), .start(start_pulse), .busy(busy), .done(done),
         .seg_addr(seg_raddr), .seg_data(seg_rdata), .result_flat(result_flat));

    assign corr_done = done;

    // ---- SPI slave streams the 144 result bytes ----
    spi_slave #(.NBYTES(144)) u_spi
        (.clk(clk), .rst(rst), .sck(spi_sck), .cs_n(spi_cs_n),
         .mosi(spi_mosi), .miso(spi_miso), .result_flat(result_flat));

    assign led = {done, busy, crc_ok, loaded_l};
endmodule
