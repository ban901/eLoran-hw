// ============================================================================
//  spi_slave.v - SPI mode 0 slave, read-only.  Streams result bytes on MISO.
//  MCU (master) pulls CS low and clocks 144 bytes; FPGA returns
//  result_flat byte 0,1,2,...  MSB-first within each byte.
//  MOSI is ignored (control is via corr_start / corr_done GPIO, not SPI).
//  FPGA clk (100 MHz) oversamples the ~10.5 MHz SCK -> robust CDC.
// ============================================================================
module spi_slave #(
    parameter integer NBYTES = 144
)(
    input  wire        clk,
    input  wire        rst,
    // SPI (from MCU master)
    input  wire        sck,
    input  wire        cs_n,
    input  wire        mosi,       // unused
    output wire        miso,
    // data source
    input  wire [NBYTES*8-1:0] result_flat
);
    // ---- synchronize async SPI lines ----
    reg [2:0] sck_q, cs_q;
    always @(posedge clk) begin
        if (rst) begin sck_q<=0; cs_q<=3'b111; end
        else begin sck_q<={sck_q[1:0],sck}; cs_q<={cs_q[1:0],cs_n}; end
    end
    wire cs_active  = ~cs_q[2];
    wire cs_falling = (cs_q[2:1]==2'b10);
    wire sck_fall   = (sck_q[2:1]==2'b10);   // mode 0: shift out on falling edge

    // ---- byte / bit tracking ----
    reg [7:0] cur_byte;
    reg [7:0] byte_idx;      // 0..NBYTES-1
    reg [2:0] bitpos;        // 0=MSB .. 7=LSB

    always @(posedge clk) begin
        if (rst) begin
            byte_idx<=0; bitpos<=0; cur_byte<=0;
        end else if (cs_falling) begin
            byte_idx <= 0;
            bitpos   <= 0;
            cur_byte <= result_flat[7:0];             // byte 0
        end else if (cs_active && sck_fall) begin
            if (bitpos==3'd7) begin
                bitpos   <= 0;
                byte_idx <= byte_idx + 1'b1;
                cur_byte <= result_flat[(byte_idx+1)*8 +: 8];
            end else begin
                bitpos <= bitpos + 1'b1;
            end
        end
    end

    assign miso = cur_byte[7-bitpos];    // point-to-point: drive continuously
endmodule
