# Script de Síntesis OOC para Vivado
# Definición de la familia FPGA (Ajustar a la placa objetivo, ej. Zynq 7000)
set part_number "xc7z020clg400-1"

# 1. Leer los archivos fuente en el orden correcto de dependencias
read_verilog -sv ../rtl/mdr_bob_pkg.sv
read_verilog -sv ../rtl/mdr_rom_pkg.sv
read_verilog -sv ../rtl/mdr_bob_datapath.sv
read_verilog -sv ../rtl/mdr_bob_fsm.sv
read_verilog -sv ../rtl/mdr_bob_top.sv

# 2. Ejecutar la síntesis lógica Out-of-Context
# El switch -mode out_of_context es crítico para evitar optimización de I/O
synth_design -top mdr_bob_top -part $part_number -mode out_of_context

# 3. Restricciones de reloj virtuales (100 MHz = 10 ns)
create_clock -name clk -period 10.0 [get_ports clk]

# 4. Generación de Reportes
report_utilization -file utilization_report.txt
report_timing_summary -file timing_report.txt

# Finalizar script
exit
