#!/usr/bin/env python3
"""
================================================================================
SCRIPT AUTOMATIZADO DE STREAMING Y SEGURIDAD CUANTICA EN PYNQ-Z2 (BOB SUBSYSTEM)
================================================================================
Este script:
1. Detecta la placa PYNQ-Z2 conectada por JTAG y UART.
2. Programa la FPGA con el bitstream del acelerador de Bob (design_1_wrapper.bit).
3. Configura el sistema de procesamiento PS7 (ps7_init.tcl).
4. Carga e inicia la aplicacion baremetal de Bob (cvqkd_bob_app.elf).
5. Captura y muestra la telemetria en vivo de streaming y seguridad por UART.
================================================================================
"""

import sys
import os
import time
import subprocess
import threading
import glob

XSDB_PATH    = "/home/drg/AMD/Xilin/2025.2/Vitis/bin/xsdb"
BIT_PATH     = "/home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_app/_ide/bitstream/design_1_wrapper.bit"
PS7_INIT_TCL = "/home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_app/_ide/psinit/ps7_init.tcl"
ELF_PATH     = "/home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_app/build/cvqkd_bob_app.elf"
NEXYS_UART   = "/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A904CVHB-if00-port0"

def find_pynq_uart():
    """Detecta el puerto serie FTDI de la PYNQ-Z2 (excluyendo la Nexys)."""
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

def launch_xsdb(program_bitstream=True):
    fpga_cmd = f"""
targets -set -nocase -filter {{name =~ "*xc7z020*"}}
puts "=== PROGRAMANDO FPGA (design_1_wrapper.bit) ==="
fpga -f "{BIT_PATH}"
after 500
""" if program_bitstream else ""

    xsdb_cmd = f"""
connect
{fpga_cmd}
targets -set -nocase -filter {{name =~ "*Cortex-A9*#0"}}
catch {{stop}}
catch {{rst -processor}}
after 200
puts "=== INICIALIZANDO PS7 (ps7_init) ==="
source "{PS7_INIT_TCL}"
ps7_init
ps7_post_config
puts "=== DESCARGANDO ELF (cvqkd_bob_app.elf) ==="
dow "{ELF_PATH}"
puts "=== INICIANDO EJECUCION EN CORTEX-A9 ==="
con
exit
"""
    tcl_file = f"/tmp/run_bob_streaming_{os.getpid()}.tcl"
    try:
        with open(tcl_file, "w") as f:
            f.write(xsdb_cmd)
            
        print(f"[XSDB] Programando PYNQ-Z2 (Bitstream: {os.path.basename(BIT_PATH)}, ELF: {os.path.basename(ELF_PATH)})...")
        res = subprocess.run([XSDB_PATH, tcl_file], capture_output=True, text=True)
        if res.returncode != 0:
            print("[XSDB ERROR]:")
            print(res.stderr)
            print(res.stdout)
            return False
        print("[XSDB] FPGA configurada, procesador ARM inicializado y aplicacion en ejecucion.")
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
    attrs[6][termios.VTIME] = 10 # 1.0s timeout
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)
    f = os.fdopen(fd, 'r', encoding='utf-8', errors='ignore')

    t_end = time.time() + duration
    print("[UART] Escuchando telemetria en vivo de Bob (PYNQ-Z2):\n")
    while time.time() < t_end:
        line = f.readline()
        if line:
            clean_line = line.strip('\r\n')
            if clean_line:
                print(f"[PYNQ-BOB] {clean_line}")
                if "SUBSISTEMA BOB COMPLETADO Y VERIFICADO" in clean_line:
                    t_end = time.time() + 2.0 # Margen para los ultimos caracteres
        else:
            time.sleep(0.01)
    f.close()

def main():
    print("=" * 72)
    print("   EJECUTOR AUTOMATIZADO DE BOB STREAMING & SEGURIDAD (PYNQ-Z2)")
    print("=" * 72)
    
    port = find_pynq_uart()
    if not port:
        print("[ERROR] No se encontro puerto serie de PYNQ-Z2.")
        sys.exit(1)
        
    print(f"[DETECCION] Detectado puerto UART de PYNQ: {port}")
    
    # Iniciar hilo de lectura UART ANTES de lanzar XSDB para no perder el arranque
    t_uart = threading.Thread(target=read_uart, args=(port, 115200, 35))
    t_uart.daemon = True
    t_uart.start()
    
    time.sleep(1.0)
    
    # Lanzar programacion y ejecucion
    success = launch_xsdb(program_bitstream=True)
    if not success:
        print("[ERROR] Fallo al programar la PYNQ-Z2 via XSDB.")
        sys.exit(1)
        
    # Esperar a que el hilo UART termine
    t_uart.join(timeout=35)
    print("\n[FIN] Sesion de ejecucion finalizada.")

if __name__ == "__main__":
    main()
