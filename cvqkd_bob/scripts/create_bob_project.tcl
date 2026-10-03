# ==============================================================================
# Recrea el proyecto Vivado de Bob (PYNQ-Z2) a partir de las fuentes del repositorio.
#
# Uso:
#   vivado -mode batch -source cvqkd_bob/scripts/create_bob_project.tcl -tclargs <dir_proyecto>
#
# El diseño de bloques reproduce el hardware que funcionó en placa (XSA del
# 22/09/2026): PS7 a 650 MHz, FCLK0 a 70 MHz, 3 AXI DMA y el wrapper de Bob.
# El wrapper (Verilog, requisito de las referencias a módulo) se instancia
# directamente desde cvqkd_bob/rtl: no hay que reempaquetar ninguna IP tras
# cambiar el RTL.
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize "$script_dir/../.."]
if { [llength $argv] < 1 } {
    error "Indica el directorio del proyecto: -tclargs <dir_proyecto>"
}
set proj_dir [file normalize [lindex $argv 0]]

# 1. Proyecto y fuentes ---------------------------------------------------------
create_project cvqkd_bob $proj_dir -part xc7z020clg400-1

add_files [glob $repo_dir/cvqkd_bob/rtl/*.sv $repo_dir/cvqkd_bob/rtl/*.v]
add_files [list \
    $repo_dir/cvqkd_alice/rtl/bg1_rom_pkg.sv \
    $repo_dir/cvqkd_mdr/rtl/mdr_rom_pkg.sv \
    $repo_dir/cvqkd_mdr/rtl/mdr_bob_datapath.sv \
    $repo_dir/cvqkd_mdr/rtl/mdr_bob_streaming.sv]

# Cores de Xilinx usados por el DSP y el estimador (se copian al proyecto)
foreach ip {cordic_vect_ip cordic_rot_ip cordic_sqrt_q16_16 div_gen_48_32_params} {
    import_ip $repo_dir/cvqkd_bob/ip/$ip/$ip.xci
}
upgrade_ip [get_ips]
generate_target all [get_ips]

update_compile_order -fileset sources_1

# 2. Diseño de bloques ----------------------------------------------------------
create_bd_design design_1

create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR
create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO

# Processing System con el preset de la PYNQ-Z2
source $script_dir/pynq_z2_ps7_preset.tcl
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
set preset [apply_preset $ps7]
foreach key [dict keys $preset CONFIG.PCW_*_AXI_*_FREQMHZ] { dict unset preset $key } ;# solo lectura
set_property -dict $preset $ps7
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {70} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1}] $ps7
connect_bd_intf_net [get_bd_intf_pins $ps7/DDR]      [get_bd_intf_ports DDR]
connect_bd_intf_net [get_bd_intf_pins $ps7/FIXED_IO] [get_bd_intf_ports FIXED_IO]

# Acelerador de Bob
set bob [create_bd_cell -type module -reference cvqkd_bob_axi_wrapper cvqkd_bob_axi_wrapper_0]

# DMA 0: ADC -> Bob (MM2S, 32 b) y MDR -> DDR (S2MM, 256 b). La trama MDR completa
# (104.448 B) llega en una sola transferencia: registro de longitud de 17 bits.
set dma0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_length_width {17} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_s2mm_burst_size {16} \
    CONFIG.c_m_axi_s2mm_data_width {256}] $dma0

# DMA 1: muestras de Alice -> Bob (MM2S, 32 b) y síndrome -> DDR (S2MM, 512 b)
set dma1 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_1]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_length_width {14} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_s2mm_burst_size {16} \
    CONFIG.c_m_axi_s2mm_data_width {512}] $dma1

# DMA 2: máscara de sacrificio -> Bob (solo MM2S, 32 b)
set dma2 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_2]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_length_width {14} \
    CONFIG.c_include_s2mm {0} \
    CONFIG.c_m_axis_mm2s_tdata_width {32}] $dma2

# Streams
connect_bd_intf_net [get_bd_intf_pins $dma0/M_AXIS_MM2S] [get_bd_intf_pins $bob/s_axis_pq]
connect_bd_intf_net [get_bd_intf_pins $dma1/M_AXIS_MM2S] [get_bd_intf_pins $bob/s_axis_alice]
connect_bd_intf_net [get_bd_intf_pins $dma2/M_AXIS_MM2S] [get_bd_intf_pins $bob/s_axis_mask]
connect_bd_intf_net [get_bd_intf_pins $bob/m_axis_mdr]      [get_bd_intf_pins $dma0/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins $bob/m_axis_syndrome] [get_bd_intf_pins $dma1/S_AXIS_S2MM]

# Control (GP0 -> AXI-Lite de los DMA y del acelerador)
set smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {4}] $smc
connect_bd_intf_net [get_bd_intf_pins $ps7/M_AXI_GP0] [get_bd_intf_pins $smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $smc/M00_AXI] [get_bd_intf_pins $dma0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $smc/M01_AXI] [get_bd_intf_pins $dma1/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $smc/M02_AXI] [get_bd_intf_pins $dma2/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $smc/M03_AXI] [get_bd_intf_pins $bob/s_axi]

# Datos (masters de los DMA -> HP0 -> DDR)
set mem [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon]
set_property -dict [list CONFIG.NUM_SI {5} CONFIG.NUM_MI {1}] $mem
connect_bd_intf_net [get_bd_intf_pins $dma0/M_AXI_MM2S] [get_bd_intf_pins $mem/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $dma0/M_AXI_S2MM] [get_bd_intf_pins $mem/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins $dma1/M_AXI_MM2S] [get_bd_intf_pins $mem/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins $dma1/M_AXI_S2MM] [get_bd_intf_pins $mem/S03_AXI]
connect_bd_intf_net [get_bd_intf_pins $dma2/M_AXI_MM2S] [get_bd_intf_pins $mem/S04_AXI]
connect_bd_intf_net [get_bd_intf_pins $mem/M00_AXI] [get_bd_intf_pins $ps7/S_AXI_HP0]

# Reloj y reset únicos (FCLK0)
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0]
connect_bd_net [get_bd_pins $ps7/FCLK_RESET0_N] [get_bd_pins $rst/ext_reset_in]
set clk_pins [get_bd_pins -of_objects [list $ps7 $rst $dma0 $dma1 $dma2 $smc $mem] -filter {TYPE == clk && DIR == I}]
foreach pin [concat $clk_pins [get_bd_pins $bob/aclk]] {
    connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] $pin
}
foreach pin [concat [get_bd_pins $bob/aresetn] [get_bd_pins $dma0/axi_resetn] [get_bd_pins $dma1/axi_resetn] \
                    [get_bd_pins $dma2/axi_resetn] [get_bd_pins $smc/aresetn] [get_bd_pins $mem/*ARESETN]] {
    connect_bd_net [get_bd_pins $rst/peripheral_aresetn] $pin
}

# Interrupciones de los DMA (el firmware actual sondea, pero quedan disponibles)
set irq [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0]
set_property CONFIG.NUM_PORTS {5} $irq
connect_bd_net [get_bd_pins $dma1/mm2s_introut] [get_bd_pins $irq/In0]
connect_bd_net [get_bd_pins $dma0/s2mm_introut] [get_bd_pins $irq/In1]
connect_bd_net [get_bd_pins $dma0/mm2s_introut] [get_bd_pins $irq/In2]
connect_bd_net [get_bd_pins $dma2/mm2s_introut] [get_bd_pins $irq/In3]
connect_bd_net [get_bd_pins $dma1/s2mm_introut] [get_bd_pins $irq/In4]
connect_bd_net [get_bd_pins $irq/dout] [get_bd_pins $ps7/IRQ_F2P]

# Mapa de direcciones (el mismo que usa el firmware)
assign_bd_address -offset 0x40000000 -range 4K  [get_bd_addr_segs $bob/s_axi/reg0]
assign_bd_address -offset 0x40400000 -range 64K [get_bd_addr_segs $dma0/S_AXI_LITE/Reg]
assign_bd_address -offset 0x40410000 -range 64K [get_bd_addr_segs $dma1/S_AXI_LITE/Reg]
assign_bd_address -offset 0x40420000 -range 64K [get_bd_addr_segs $dma2/S_AXI_LITE/Reg]
assign_bd_address

validate_bd_design
save_bd_design

# 3. Wrapper HDL como top -------------------------------------------------------
add_files -norecurse [make_wrapper -files [get_files design_1.bd] -top]
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "Proyecto de Bob creado en $proj_dir"
