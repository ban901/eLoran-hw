## ============================================================================
##  corr_pins.xdc - Basys3 (Artix-7 xc7a35tcpg236-1) for corr_top
## ============================================================================

## 100 MHz clock
set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## Reset - center button (btnC)
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports rst_btn]

## USB-RS232 : PC -> FPGA (Basys3 on-board USB-UART, same micro-USB as programming)
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports uart_rx]  ;# RsRx

## ---- Pmod JC : link to STM32 (MCU) ----
## JC1 <- MCU PB13 SCK  (CN10-30)
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports spi_sck]
## JC2 <- MCU PB12 CS   (CN10-16)
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports spi_cs_n]
## JC3 <- MCU PB15 MOSI (CN10-26)   (unused, wired for flexibility)
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports spi_mosi]
## JC4 -> MCU PB14 MISO (CN10-28)
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports spi_miso]
## JC7 <- MCU START gpio (e.g. PB1 / CN10-24)
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports corr_start]
## JC8 -> MCU DONE  gpio (e.g. PB2 / CN10-22, EXTI)
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports corr_done]
## GND : Pmod JC pin 5 or 11  ->  MCU CN10-9   (jumper only, no VCC)

## ---- status LEDs ----  led = {done, busy, crc_ok, loaded}
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

## SPI clock (~10.5 MHz) is oversampled by the 100 MHz domain, so no create_clock
## on spi_sck is required. Treat SPI/START/DONE as async I/O.
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO     [current_design]

set_property PULLTYPE PULLDOWN [get_ports corr_start]
set_property PULLTYPE PULLUP   [get_ports spi_cs_n]