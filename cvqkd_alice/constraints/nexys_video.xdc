## ============================================================================
## Restricciones Físicas y de Pines para Digilent Nexys Video (Artix-7 XC7A200T)
## Proyecto: cvqkd_alice
## ============================================================================

## 1. Oscilador de Reloj del Sistema (100 MHz en Pin R4)
set_property PACKAGE_PIN R4 [get_ports clk_100MHz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100MHz]
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets design_1_i/clk_wiz_1/clk_in1]

## 2. Pulsador de Reset (Botón CPU RESET "PROG" - Activo a nivel Bajo)
set_property PACKAGE_PIN G4 [get_ports reset_rtl_0]
set_property IOSTANDARD LVCMOS15 [get_ports reset_rtl_0]

## 3. Puerto Serie USB-UART (FT232R en Nexys Video)
set_property PACKAGE_PIN V18 [get_ports uart_rtl_0_rxd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rtl_0_rxd]

set_property PACKAGE_PIN AA19 [get_ports uart_rtl_0_txd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rtl_0_txd]

## 4. Opciones de Configuración de Bitstream para memoria Flash QSPI
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
