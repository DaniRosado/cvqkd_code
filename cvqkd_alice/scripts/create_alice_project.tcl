# ==============================================================================
# Recrea el proyecto Vivado de Alice (Nexys Video) a partir de las fuentes del repositorio.
#
# Uso:
#   vivado -mode batch -source cvqkd_alice/scripts/create_alice_project.tcl -tclargs <dir_proyecto>
#
# El diseño de bloques reproduce el que funcionó en placa (29/09/2026): MicroBlaze
# con 16 KB de memoria local, reloj de 25 MHz, UART Lite (9600 baudios) y el wrapper
# de Alice. El wrapper (Verilog, requisito de las referencias a módulo) se instancia
# directamente desde cvqkd_alice/rtl: no hay que reempaquetar ninguna IP tras
# cambiar el RTL. Los vectores de MATLAB que inicializan las memorias del wrapper se
# añaden como "Memory Initialization Files", así que $readmemh los encuentra por nombre.
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize "$script_dir/../.."]
if { [llength $argv] < 1 } {
    error "Indica el directorio del proyecto: -tclargs <dir_proyecto>"
}
set proj_dir [file normalize [lindex $argv 0]]

# 1. Proyecto y fuentes ---------------------------------------------------------
create_project cvqkd_alice $proj_dir -part xc7a200tsbg484-1

add_files [glob $repo_dir/cvqkd_alice/rtl/*.sv $repo_dir/cvqkd_alice/rtl/*.v]
add_files [list \
    $repo_dir/cvqkd_mdr/rtl/mdr_alice_fsm.sv \
    $repo_dir/cvqkd_mdr/rtl/mdr_alice_datapath.sv \
    $repo_dir/cvqkd_mdr/rtl/mdr_alice_top.sv]

set data_dir $repo_dir/cvqkd_matlab/data
set mem_files [add_files -norecurse [list \
    $data_dir/alice_mdr_inputs.txt \
    $data_dir/expected_m_messages.txt \
    $data_dir/alice_k_dynamic.txt \
    $data_dir/expected_syndrome_words.hex]]
set_property file_type {Memory Initialization Files} $mem_files

add_files -fileset constrs_1 $repo_dir/cvqkd_alice/constraints/nexys_video.xdc

# Testbenches (con sus vectores) para simular desde la interfaz de Vivado
add_files -fileset sim_1 [glob $repo_dir/cvqkd_alice/sim/*.sv]
set sim_mem [add_files -fileset sim_1 -norecurse [list \
    $data_dir/u_bits.txt \
    $data_dir/expected_syndrome.txt \
    $data_dir/block_bits.txt]]
set_property file_type {Memory Initialization Files} $sim_mem
set_property top tb_alice_post_processing_core [get_filesets sim_1]

update_compile_order -fileset sources_1

# 2. Diseño de bloques ----------------------------------------------------------
create_bd_design design_1

create_bd_port -dir I -type clk -freq_hz 100000000 clk_100MHz
create_bd_port -dir I -type rst reset_rtl_0
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports reset_rtl_0]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 uart_rtl_0

# Reloj del sistema: 100 MHz de la placa -> 25 MHz
set clk_wiz [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_1]
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000}] $clk_wiz
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_wiz_1_100M]

# MicroBlaze con memoria local de instrucciones y datos (LMB)
set mb [create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze:11.0 microblaze_0]
set_property -dict [list \
    CONFIG.C_DEBUG_ENABLED {1} \
    CONFIG.C_D_AXI {1} \
    CONFIG.C_D_LMB {1} \
    CONFIG.C_I_LMB {1} \
    CONFIG.C_USE_BARREL {1} \
    CONFIG.C_ENABLE_CONVERSION {0}] $mb
set mdm [create_bd_cell -type ip -vlnv xilinx.com:ip:mdm:3.2 mdm_1]

set lmem [create_bd_cell -type hier microblaze_0_local_memory]
foreach bus {dlmb ilmb} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 $lmem/${bus}_v10
    set ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 $lmem/${bus}_bram_if_cntlr]
    set_property CONFIG.C_ECC {0} $ctrl
}
set lmb_bram [create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 $lmem/lmb_bram]
set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.use_bram_block {BRAM_Controller}] $lmb_bram
connect_bd_intf_net [get_bd_intf_pins $mb/DLMB] [get_bd_intf_pins $lmem/dlmb_v10/LMB_M]
connect_bd_intf_net [get_bd_intf_pins $mb/ILMB] [get_bd_intf_pins $lmem/ilmb_v10/LMB_M]
connect_bd_intf_net [get_bd_intf_pins $lmem/dlmb_v10/LMB_Sl_0] [get_bd_intf_pins $lmem/dlmb_bram_if_cntlr/SLMB]
connect_bd_intf_net [get_bd_intf_pins $lmem/ilmb_v10/LMB_Sl_0] [get_bd_intf_pins $lmem/ilmb_bram_if_cntlr/SLMB]
connect_bd_intf_net [get_bd_intf_pins $lmem/dlmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins $lmb_bram/BRAM_PORTA]
connect_bd_intf_net [get_bd_intf_pins $lmem/ilmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins $lmb_bram/BRAM_PORTB]
connect_bd_intf_net [get_bd_intf_pins $mdm/MBDEBUG_0] [get_bd_intf_pins $mb/DEBUG]

# Periféricos: UART Lite, acelerador de Alice y 2 AXI DMA (sin SG ni S2MM)
set uart [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 axi_uartlite_0]
set alice [create_bd_cell -type module -reference cvqkd_alice_axi_wrapper cvqkd_alice_axi_wrap_0]
foreach i {0 1} {
    set dma($i) [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_$i]
    set_property -dict [list CONFIG.c_include_s2mm {0} CONFIG.c_include_sg {0}] $dma($i)
}
connect_bd_intf_net [get_bd_intf_pins $uart/UART] [get_bd_intf_ports uart_rtl_0]
connect_bd_intf_net [get_bd_intf_pins $dma(0)/M_AXIS_MM2S] [get_bd_intf_pins $alice/s_axis_x]
connect_bd_intf_net [get_bd_intf_pins $dma(1)/M_AXIS_MM2S] [get_bd_intf_pins $alice/s_axis_m]

set ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0]
set_property CONFIG.NUM_MI {4} $ic
connect_bd_intf_net [get_bd_intf_pins $mb/M_AXI_DP]       [get_bd_intf_pins $ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $ic/M00_AXI] [get_bd_intf_pins $uart/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $ic/M01_AXI] [get_bd_intf_pins $alice/s_axi]
connect_bd_intf_net [get_bd_intf_pins $ic/M02_AXI] [get_bd_intf_pins $dma(0)/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $ic/M03_AXI] [get_bd_intf_pins $dma(1)/S_AXI_LITE]

# Reloj y reset
connect_bd_net [get_bd_ports clk_100MHz] [get_bd_pins $clk_wiz/clk_in1]
connect_bd_net [get_bd_pins $mdm/Debug_SYS_Rst] [get_bd_pins $clk_wiz/reset]
connect_bd_net [get_bd_ports reset_rtl_0] [get_bd_pins $rst/ext_reset_in]
set clk_pins [get_bd_pins -of_objects [list $rst $mb $uart $dma(0) $dma(1) $ic] -filter {TYPE == clk && DIR == I}]
foreach pin [concat $clk_pins [get_bd_pins $lmem/*/LMB_Clk] [get_bd_pins $alice/aclk]] {
    connect_bd_net [get_bd_pins $clk_wiz/clk_out1] $pin
}
connect_bd_net [get_bd_pins $rst/mb_reset] [get_bd_pins $mb/Reset]
foreach pin [concat [get_bd_pins $lmem/*_v10/SYS_Rst] [get_bd_pins $lmem/*_bram_if_cntlr/LMB_Rst]] {
    connect_bd_net [get_bd_pins $rst/bus_struct_reset] $pin
}
foreach pin [concat [get_bd_pins $ic/*ARESETN] [get_bd_pins $uart/s_axi_aresetn] [get_bd_pins $dma(0)/axi_resetn] \
                    [get_bd_pins $dma(1)/axi_resetn] [get_bd_pins $alice/aresetn]] {
    connect_bd_net [get_bd_pins $rst/peripheral_aresetn] $pin
}

# Mapa de direcciones (el mismo que usa el firmware)
set data_space [get_bd_addr_spaces $mb/Data]
assign_bd_address -offset 0x00000000 -range 16K -target_address_space $data_space [get_bd_addr_segs $lmem/dlmb_bram_if_cntlr/SLMB/Mem]
assign_bd_address -offset 0x00000000 -range 16K -target_address_space [get_bd_addr_spaces $mb/Instruction] [get_bd_addr_segs $lmem/ilmb_bram_if_cntlr/SLMB/Mem]
assign_bd_address -offset 0x00004000 -range 8K  -target_address_space $data_space [get_bd_addr_segs $alice/s_axi/reg0]
assign_bd_address -offset 0x40600000 -range 64K -target_address_space $data_space [get_bd_addr_segs $uart/S_AXI/Reg]
assign_bd_address -offset 0x41E00000 -range 64K -target_address_space $data_space [get_bd_addr_segs $dma(0)/S_AXI_LITE/Reg]
assign_bd_address -offset 0x41E10000 -range 64K -target_address_space $data_space [get_bd_addr_segs $dma(1)/S_AXI_LITE/Reg]

validate_bd_design
save_bd_design

# 3. Wrapper HDL como top -------------------------------------------------------
add_files -norecurse [make_wrapper -files [get_files design_1.bd] -top]
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "Proyecto de Alice creado en $proj_dir"
