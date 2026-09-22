open_project /home/drg/VivadoProyects/cvqkd_alice/cvqkd_alice.xpr

# Resetear runs previos
reset_run synth_1

puts "=== [INFO] Lanzando Sintesis e Implementacion de Alice (jobs=4)... ==="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "=== [STATUS] Estado final de la implementacion: $impl_status ==="

if { [string match "*Complete*" $impl_status] } {
    write_hw_platform -fixed -include_bit -force -file /home/drg/VivadoProyects/cvqkd_alice/design_1_wrapper.xsa
    puts {=== [OK] Bitstream e informe XSA exportados exitosamente en /home/drg/VivadoProyects/cvqkd_alice/design_1_wrapper.xsa ===}
} else {
    puts "=== [ERROR] La implementacion no se completo correctamente: $impl_status ==="
}
