#!/usr/bin/env python3
"""
================================================================================
SCRIPT AUTOMATIZADO DE BENCHMARK EN PYNQ-Z2 (ARM CORTEX-A9 @ 650 MHz)
================================================================================
Este script programa el binario ELF de benchmark en el procesador ARM Cortex-A9
de la placa PYNQ-Z2 utilizando XSDB (Xilinx System Debugger) y captura la salida
por UART para medir la latencia, throughput y speedup frente a la FPGA Nexys Video.
================================================================================
"""

import sys
import os
import time
import subprocess
import threading
import glob

XSDB_PATH    = "/home/drg/AMD/Xilin/2025.2/Vitis/bin/xsdb"
PS7_INIT_TCL = "/home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_app/_ide/psinit/ps7_init.tcl"
ELF_PATH     = "/home/drg/TFG/cvqkd_code/benchmark/cvqkd_benchmark_pynq_arm.elf"
NEXYS_UART   = "/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A904CVHB-if00-port0"

def find_pynq_uart():
    """Detecta el puerto serie FTDI de la PYNQ-Z2 (excluyendo la Nexys)."""
    by_id_ports = glob.glob("/dev/serial/by-id/*")
    pynq_ports = [p for p in by_id_ports if p != NEXYS_UART]
    if pynq_ports:
        return pynq_ports[0]
    
    # Fallback buscando ttyUSB
    tty_ports = sorted(glob.glob("/dev/ttyUSB*"))
    if len(tty_ports) > 1:
        return tty_ports[1] # La segunda interfaz suele ser la PYNQ si la Nexys es USB0
    elif len(tty_ports) == 1:
        return tty_ports[0]
    return None

def launch_xsdb():
    xsdb_cmd = f"""
connect
puts "=== CONECTADO A JTAG ==="
targets
# Seleccionar PS7
targets -set -nocase -filter {{name =~ "*ps7_init*" || name =~ "*PS7*" || name =~ "*ARM*#0" || name =~ "*Cortex-A9*#0"}}
catch {{rst -system}}
after 1000
targets -set -nocase -filter {{name =~ "*Cortex-A9*#0"}}
catch {{rst -processor}}
source {PS7_INIT_TCL}
ps7_init
ps7_post_config
dow {ELF_PATH}
puts "=== EJECUTANDO BENCHMARK EN ARM CORTEX-A9 ==="
con
exit
"""
    tcl_file = "/tmp/run_pynq_bench.tcl"
    with open(tcl_file, "w") as f:
        f.write(xsdb_cmd)
        
    print(f"[XSDB] Programando {ELF_PATH} en el procesador ARM Cortex-A9 de PYNQ-Z2...")
    res = subprocess.run([XSDB_PATH, tcl_file], capture_output=True, text=True)
    if res.returncode != 0:
        print("[XSDB ERROR]:")
        print(res.stderr)
        print(res.stdout)
        return False
    print("[XSDB] Binario cargado y procesador iniciado con exito.")
    return True

def read_uart(port, baud=115200, duration=15):
    import serial
    print(f"[UART] Conectando a {port} a {baud} baudios...")
    try:
        ser = serial.Serial(port, baud, timeout=1.0)
    except Exception as e:
        print(f"[UART ERROR] No se pudo abrir {port}: {e}")
        return

    ser.reset_input_buffer()
    t_end = time.time() + duration
    print("[UART] Escuchando resultados de PYNQ-Z2:\n")
    while time.time() < t_end:
        line = ser.readline().decode('utf-8', errors='replace')
        if line:
            print(f"[PYNQ-ARM] {line.strip()}")
            if "RESUMEN FINAL BENCHMARK" in line:
                t_end = time.time() + 3.0 # Dar tiempo a que termine de volcar el resumen
    ser.close()

def main():
    print("========================================================================")
    print("   EJECUTOR AUTOMATIZADO DE BENCHMARK EN PYNQ-Z2 (ARM CORTEX-A9)       ")
    print("========================================================================")
    
    port = find_pynq_uart()
    if not port:
        print("[AVISO] No se detecto puerto UART adicional para la PYNQ-Z2.")
        print("Asegurate de que el cable micro-USB de la PYNQ-Z2 esta conectado al PC.")
        print("Puertos actuales detectados:", glob.glob("/dev/ttyUSB*"))
        sys.exit(1)

    print(f"[DETECCION] Detectado puerto UART de PYNQ: {port}")
    
    # Lanzar lectura UART en hilo concurrente
    t_uart = threading.Thread(target=read_uart, args=(port, 115200, 20))
    t_uart.daemon = True
    t_uart.start()

    time.sleep(1.0)
    if not launch_xsdb():
        sys.exit(1)

    t_uart.join(timeout=25)
    print("\n[FIN] Medicion completada.")

if __name__ == "__main__":
    main()
