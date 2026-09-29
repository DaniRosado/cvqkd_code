#!/usr/bin/env python3
"""
================================================================================
SCRIPT AUTOMATIZADO DE BENCHMARK SOFTWARE BOB EN PYNQ-Z2 (ARM CORTEX-A9)
================================================================================
Ejecuta el pipeline completo de software de Bob (Fase, Estimacion, MDR, Sindrome,
Holevo) en el procesador ARM Cortex-A9 Baremetal (@ 650 MHz) y mide con precision
de ciclos de reloj la latencia por etapa para comparar contra el acelerador FPGA.
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
ELF_PATH     = "/home/drg/TFG/cvqkd_code/benchmark/cvqkd_bob_benchmark_pynq_arm.elf"
NEXYS_UART   = "/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A904CVHB-if00-port0"

def find_pynq_uart():
    by_id_ports = glob.glob("/dev/serial/by-id/*")
    pynq_ports = [p for p in by_id_ports if p != NEXYS_UART]
    if pynq_ports:
        return pynq_ports[0]
    
    tty_ports = sorted(glob.glob("/dev/ttyUSB*"))
    if len(tty_ports) > 1:
        return tty_ports[1]
    elif len(tty_ports) == 1:
        return tty_ports[0]
    return None

def launch_xsdb():
    xsdb_cmd = f"""
connect
targets -set -nocase -filter {{name =~ "*Cortex-A9*#0"}}
catch {{stop}}
catch {{rst -processor}}
after 200
puts "=== INICIALIZANDO PS7 ==="
source "{PS7_INIT_TCL}"
ps7_init
ps7_post_config
puts "=== DESCARGANDO ELF BENCHMARK BOB (ARM) ==="
dow "{ELF_PATH}"
puts "=== INICIANDO BENCHMARK EN CORTEX-A9 ==="
con
exit
"""
    tcl_file = f"/tmp/run_bob_bench_arm_{os.getpid()}.tcl"
    try:
        with open(tcl_file, "w") as f:
            f.write(xsdb_cmd)
            
        print(f"[XSDB] Programando {os.path.basename(ELF_PATH)} en ARM Cortex-A9...")
        res = subprocess.run([XSDB_PATH, tcl_file], capture_output=True, text=True)
        if res.returncode != 0:
            print("[XSDB ERROR]:")
            print(res.stderr)
            print(res.stdout)
            return False
        print("[XSDB] Procesador ARM inicializado y benchmark en ejecucion.")
        return True
    finally:
        if os.path.exists(tcl_file):
            try:
                os.remove(tcl_file)
            except Exception:
                pass

def read_uart(port, baud=115200, duration=35):
    import termios
    print(f"[UART] Conectando a {port} a {baud} baudios...")
    baud_map = {115200: termios.B115200, 9600: termios.B9600, 57600: termios.B57600}
    try:
        fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
    except Exception as e:
        print(f"[UART ERROR] No se pudo abrir {port}: {e}")
        return

    attrs = termios.tcgetattr(fd)
    attrs[0] = termios.IGNPAR
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    b = baud_map.get(baud, termios.B115200)
    attrs[4] = b
    attrs[5] = b
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 10
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)
    f = os.fdopen(fd, 'r', encoding='utf-8', errors='ignore')

    t_end = time.time() + duration
    print("[UART] Escuchando resultados de PYNQ-Z2 (ARM Cortex-A9):\n")
    while time.time() < t_end:
        line = f.readline()
        if line:
            clean_line = line.strip('\r\n')
            if clean_line:
                print(f"[PYNQ-ARM] {clean_line}")
                if "COMPARATIVA: CPU SOFTWARE VS FPGA HARDWARE" in clean_line:
                    t_end = time.time() + 3.0
        else:
            time.sleep(0.01)
    f.close()

def main():
    print("=" * 72)
    print("   BENCHMARK SOFTWARE BOB EN PYNQ-Z2 (ARM CORTEX-A9 @ 650 MHz)")
    print("=" * 72)
    
    port = find_pynq_uart()
    if not port:
        print("[ERROR] No se encontro puerto serie de PYNQ-Z2.")
        sys.exit(1)
        
    print(f"[DETECCION] Detectado puerto UART de PYNQ: {port}")
    
    t_uart = threading.Thread(target=read_uart, args=(port, 115200, 35))
    t_uart.daemon = True
    t_uart.start()
    
    time.sleep(1.0)
    
    success = launch_xsdb()
    if not success:
        print("[ERROR] Fallo al programar la PYNQ-Z2 via XSDB.")
        sys.exit(1)
        
    t_uart.join(timeout=35)
    print("\n[FIN] Sesion de benchmark finalizada.")

if __name__ == "__main__":
    main()
