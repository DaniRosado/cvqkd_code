#!/usr/bin/env python3
import sys
import os
import argparse
import time

GOLDEN_KEY_FILE = "/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/block_bits.txt"

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

    print("\n" + "="*60)
    print("           RESULTADO DE VERIFICACION DE CLAVE CV-QKD         ")
    print("="*60)
    print(f"  Total palabras analizadas : {len(golden_words)}")
    print(f"  Total bits de clave       : {total_bits}")
    print(f"  Palabras coincidentes     : {len(golden_words) - word_errors} / {len(golden_words)}")
    print(f"  Errores de bit (BER)      : {bit_errors} / {total_bits} ({bit_errors/total_bits*100:.4f}%)")
    
    if word_errors == 0:
        print("\n  >>> [EXITO TOTAL 100%] La clave de Alice en hardware coincide")
        print("  >>> exactamente bit a bit con Bob (BER = 0.0000%).")
        print("="*60 + "\n")
        return True
    else:
        print(f"\n  >>> [FALLO] Se detectaron {word_errors} palabras con error.")
        print("="*60 + "\n")
        return False

def read_from_serial(port="/dev/ttyUSB1", baudrate=115200, timeout=10):
    print(f"[UART] Conectando a {port} a {baudrate} baudios...")
    try:
        import serial
        ser = serial.Serial(port, baudrate=baudrate, timeout=1.0)
        readline_fn = lambda: ser.readline().decode('utf-8', errors='ignore')
        close_fn = ser.close
    except ImportError:
        import termios
        import tty
        baud_map = {115200: termios.B115200, 9600: termios.B9600, 57600: termios.B57600}
        fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
        attrs = termios.tcgetattr(fd)
        attrs[0] = termios.IGNPAR
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0
        b = baud_map.get(baudrate, termios.B115200)
        termios.cfsetispeed(attrs, b)
        termios.cfsetospeed(attrs, b)
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 10 # 1.0s
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        f = os.fdopen(fd, 'r', encoding='utf-8', errors='ignore')
        readline_fn = f.readline
        close_fn = f.close

    received_words = []
    in_key = False
    start_time = time.time()
    
    print("[UART] Esperando datos de Nexys Video...")
    try:
        while time.time() - start_time < timeout:
            line = readline_fn().strip()
            if not line:
                continue
            print(f"[NEXYS] {line}")
            if line == "--- KEY_START ---":
                in_key = True
                received_words = []
                continue
            elif line == "--- KEY_END ---":
                in_key = False
                break
            elif in_key:
                try:
                    val = int(line, 16)
                    received_words.append(val)
                except ValueError:
                    pass
    finally:
        close_fn()
    return received_words

def read_from_file(filename):
    print(f"[FILE] Leyendo volcado de clave desde {filename}...")
    received_words = []
    in_key = False
    with open(filename, "r") as f:
        for line in f:
            line = line.strip()
            if line == "--- KEY_START ---":
                in_key = True
                received_words = []
                continue
            elif line == "--- KEY_END ---":
                in_key = False
                break
            elif in_key:
                try:
                    val = int(line, 16)
                    received_words.append(val)
                except ValueError:
                    pass
            elif not in_key and len(line) == 8:
                try:
                    val = int(line, 16)
                    received_words.append(val)
                except ValueError:
                    pass
    return received_words

def main():
    parser = argparse.ArgumentParser(description="Verificador de clave CV-QKD (Alice HW vs Bob)")
    parser.add_argument("--port", type=str, default="/dev/ttyUSB1", help="Puerto serie UART (ej: /dev/ttyUSB1)")
    parser.add_argument("--file", type=str, help="Archivo con volcado de terminal UART (opcional)")
    args = parser.parse_args()

    golden_words = load_golden_words()
    print(f"[INIT] Cargadas {len(golden_words)} palabras doradas de Bob (26.112 bits).")

    if args.file:
        rec_words = read_from_file(args.file)
    else:
        rec_words = read_from_serial(port=args.port)

    compare_keys(rec_words, golden_words)

if __name__ == "__main__":
    main()
