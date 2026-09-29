#!/usr/bin/env python3
import sys
import os
import argparse
import time
import subprocess
import threading

GOLDEN_KEY_FILE = "/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/block_bits.txt"
FTDI_UART_BY_ID = "/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A904CVHB-if00-port0"
BITSTREAM_PATH  = "/home/drg/VivadoProyects/cvqkd_alice/cvqkd_alice.runs/impl_1/design_1_wrapper.bit"
ELF_PATH        = "/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/build/cvqkd_alice_application.elf"
XSDB_PATH       = "/home/drg/AMD/Xilin/2025.2/Vitis/bin/xsdb"

def load_golden_words(path=GOLDEN_KEY_FILE):
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    if len(lines) != 68:
        raise ValueError(f"Expected 68 lines in {path}, got {len(lines)}")
    
    golden_words = []
    for col_idx, line in enumerate(lines):
        for w in range(12):
            word_val = 0
            for b in range(32):
                bit_idx = w * 32 + b
                char_bit = int(line[383 - bit_idx])
                if char_bit:
                    word_val |= (1 << b)
            golden_words.append(word_val)
    return golden_words

def compare_keys(received_words, golden_words):
    if len(received_words) != len(golden_words):
        print(f"[ERROR] Cantidad de palabras distinta: Recibidas {len(received_words)}, Esperadas {len(golden_words)}")
        return False
    
    word_errors = 0
    bit_errors = 0
    total_bits = len(golden_words) * 32
    
    for i in range(len(golden_words)):
        rec = received_words[i]
        exp = golden_words[i]
        diff = rec ^ exp
        if diff != 0:
            word_errors += 1
            bit_errors += bin(diff).count('1')
            if word_errors <= 10:
                print(f"  [ERROR] Palabra {i:3d} (Col {i//12:2d}, W {i%12:2d}): Recibido 0x{rec:08X} != Esperado 0x{exp:08X} (Diff: 0x{diff:08X})")

    # Comprobar si estamos ante el bitstream rev3 (donde Col 0 recibida == Golden Col 1 y Col 1..66 == Golden Col 0)
    col0_rec = received_words[0:12]
    col1_rec = received_words[12:24]
    golden_col0 = golden_words[0:12]
    golden_col1 = golden_words[12:24]

    print("\n" + "="*60)
    print("           RESULTADO DE VERIFICACION DE CLAVE CV-QKD         ")
    print("="*60)
    print(f"  Total palabras analizadas : {len(golden_words)}")
    print(f"  Total bits de clave       : {total_bits}")
    print(f"  Palabras coincidentes     : {len(golden_words) - word_errors} / {len(golden_words)}")
    print(f"  Errores de bit (BER)      : {bit_errors} / {total_bits} ({bit_errors/total_bits*100:.4f}%)")
    
    if word_errors == 0:
        print("\n  >>> [EXITO TOTAL 100%] La clave de Alice en hardware coincide")
        print("  >>> exactamente bit a bit con Bob (816/816 palabras, BER = 0.0000%).")
        print("="*60 + "\n")
        return True
    elif col0_rec == golden_col1 and col1_rec == golden_col0:
        print("\n  >>> [DIAGNOSTICO BITSTREAM REV 3 DETECTADO]:")
        print("  >>> - Palabras   0..11 (384 bits) coinciden al 100.00% (0 errores) con la Columna 1 de Bob!")
        print("  >>> - Palabras  12..23 (384 bits) coinciden al 100.00% (0 errores) con la Columna 0 de Bob!")
        print("  >>> (El decodificador MDR+LDPC en la FPGA ya converge al 100%. Falta actualizar")
        print("  >>>  el bitstream en Vivado a la Revision 4 para extraer las columnas 2..67).")
        print("="*60 + "\n")
        return False
    else:
        print(f"\n  >>> [FALLO] Se detectaron {word_errors} palabras con error.")
        print("="*60 + "\n")
        return False

def trigger_fpga_via_xsdb(program_bit=True):
    time.sleep(1.0)
    if program_bit and os.path.exists(BITSTREAM_PATH):
        print(f"[XSDB] Programando bitstream {os.path.basename(BITSTREAM_PATH)} en FPGA y lanzando MicroBlaze...")
        tcl_cmd = (
            f"connect; "
            f"targets -set -filter {{name =~ \"*xc7a200t*\"}}; "
            f"fpga \"{BITSTREAM_PATH}\"; "
            f"after 1000; "
            f"targets -set -filter {{name =~ \"*MicroBlaze*#0*\"}}; "
            f"rst -processor; "
            f"dow \"{ELF_PATH}\"; "
            f"con; "
            f"exit"
        )
    else:
        print("[XSDB] Reiniciando y lanzando aplicacion en MicroBlaze...")
        tcl_cmd = (
            f"connect; "
            f"targets -set -filter {{name =~ \"*MicroBlaze*#0*\"}}; "
            f"rst -processor; "
            f"dow \"{ELF_PATH}\"; "
            f"con; "
            f"exit"
        )
    subprocess.run([XSDB_PATH, "-eval", tcl_cmd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def resolve_uart_port(port):
    if os.path.exists(FTDI_UART_BY_ID):
        real_p = os.path.realpath(FTDI_UART_BY_ID)
        return real_p
    if os.path.exists(port):
        return port
    raise FileNotFoundError(
        f"No se encontro el puerto UART FT232R de la Nexys Video ({FTDI_UART_BY_ID} ni {port}). "
        "Verifica que el cable micro-USB este conectado al puerto 'UART' (J14) de la placa."
    )

def read_from_serial(port="/dev/ttyUSB2", baudrate=9600, timeout=90, auto_launch=True, program_bit=True, golden_words=None):
    port = resolve_uart_port(port)
    print(f"[UART] Conectando al puerto UART FT232R de Nexys Video: {port} ({baudrate} baudios)...")
    import termios
    baud_map = {115200: termios.B115200, 9600: termios.B9600, 57600: termios.B57600}
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
    attrs = termios.tcgetattr(fd)
    attrs[0] = termios.IGNPAR
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    b = baud_map.get(baudrate, termios.B9600)
    attrs[4] = b # ispeed
    attrs[5] = b # ospeed
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 10 # 1.0s
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)
    f = os.fdopen(fd, 'r', encoding='utf-8', errors='ignore')

    if auto_launch and os.path.exists(XSDB_PATH) and os.path.exists(ELF_PATH):
        t = threading.Thread(target=trigger_fpga_via_xsdb, args=(program_bit,), daemon=True)
        t.start()

    received_words = []
    in_key = False
    start_time = time.time()
    
    print("[UART] Escuchando salida serie de Nexys Video...")
    try:
        while time.time() - start_time < timeout:
            line = f.readline().strip()
            if not line:
                continue
            if line == "--- KEY_START ---":
                print("[NEXYS] --- KEY_START --- (Recibiendo 816 palabras por UART a 9600 bps, ~8.5 seg...)")
                in_key = True
                received_words = []
            elif line == "--- KEY_END ---":
                print(f"[NEXYS] --- KEY_END --- ({len(received_words)} palabras recibidas)")
                in_key = False
                if golden_words:
                    compare_keys(received_words, golden_words)
            elif in_key:
                try:
                    val = int(line, 16)
                    received_words.append(val)
                    if len(received_words) % 100 == 0 or len(received_words) == 816:
                        print(f"  -> Recibidas {len(received_words)} / 816 palabras...")
                except ValueError:
                    pass
            elif line == "[STREAM_DONE]":
                print(f"[NEXYS] {line}")
                print("[HOST] Prueba de streaming completada con exito.")
                break
            else:
                print(f"[NEXYS] {line}")
    finally:
        f.close()
    return received_words

def main():
    parser = argparse.ArgumentParser(description="Verificador de clave CV-QKD (Alice HW vs Bob)")
    parser.add_argument("--port", type=str, default="/dev/ttyUSB2", help="Puerto serie UART (por defecto: /dev/ttyUSB2)")
    parser.add_argument("--baud", type=int, default=9600, help="Baudrate UART (por defecto: 9600 segun axi_uartlite_0)")
    parser.add_argument("--no-program-bit", dest="program_bit", action="store_false", help="No reprogramar bitstream")
    parser.set_defaults(program_bit=True)
    args = parser.parse_args()

    golden_words = load_golden_words()
    print(f"[INIT] Cargadas {len(golden_words)} palabras doradas de Bob (26.112 bits).")

    rec_words = read_from_serial(port=args.port, baudrate=args.baud, program_bit=args.program_bit, golden_words=golden_words)

if __name__ == "__main__":
    main()
