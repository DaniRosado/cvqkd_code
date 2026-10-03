#!/usr/bin/env python3
"""
Ejecuta el firmware en las placas y muestra (o comprueba) la salida por UART.

    tools/run_board.py alice         Nexys Video: MicroBlaze de Alice + comparación de la clave con MATLAB
    tools/run_board.py bob           PYNQ-Z2: firmware de Bob (fases I y II)
    tools/run_board.py bench-alice   PYNQ-Z2: decodificador LDPC en software en el ARM (benchmark/)
    tools/run_board.py bench-bob     PYNQ-Z2: cadena de Bob en software en el ARM (benchmark/)

Rutas por defecto (se pueden cambiar con las opciones o con variables de entorno):
    XILINX_VITIS   instalación de Vitis (para xsdb), si xsdb no está en el PATH
    VITIS_WS       workspace de Vitis con cvqkd_alice/ y cvqkd_bob/ (por defecto ~/VitisProyects)

La UART se detecta en /dev/serial/by-id (Nexys Video: FT232R; PYNQ-Z2: segunda
interfaz del FT2232); con --port se fuerza otro puerto.
"""

import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile
import termios
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VITIS_WS = os.environ.get("VITIS_WS", os.path.expanduser("~/VitisProyects"))


def platform_hw(system):
    return os.path.join(VITIS_WS, system, f"{system}_platform", "export", f"{system}_platform", "hw")


# Configuración de cada ejecución: placa, ficheros, baudios y línea que marca el final
RUNS = {
    "alice": dict(
        board="nexys", baud=9600, timeout=180, end="[STREAM_DONE]",
        bit=os.path.join(platform_hw("cvqkd_alice"), "design_1_wrapper.bit"),
        elf=os.path.join(VITIS_WS, "cvqkd_alice", "cvqkd_alice_application", "build", "cvqkd_alice_application.elf")),
    "bob": dict(
        board="pynq", baud=115200, timeout=600, end="Tasa Clave Secreta en Vivo",
        bit=os.path.join(platform_hw("cvqkd_bob"), "design_1_wrapper.bit"),
        elf=os.path.join(VITIS_WS, "cvqkd_bob", "cvqkd_bob_app", "build", "cvqkd_bob_app.elf")),
    "bench-alice": dict(
        board="pynq", baud=115200, timeout=60, end="Factor de Aceleracion", bit=None,
        elf=os.path.join(REPO, "benchmark", "cvqkd_benchmark_pynq_arm.elf")),
    "bench-bob": dict(
        board="pynq", baud=115200, timeout=60, end="SPEEDUP ACELERADOR FPGA", bit=None,
        elf=os.path.join(REPO, "benchmark", "cvqkd_bob_benchmark_pynq_arm.elf")),
}


def find_xsdb():
    xsdb = shutil.which("xsdb")
    if not xsdb and os.environ.get("XILINX_VITIS"):
        xsdb = os.path.join(os.environ["XILINX_VITIS"], "bin", "xsdb")
    if not xsdb or not os.path.exists(xsdb):
        sys.exit("No se encuentra xsdb: añade Vitis al PATH o define XILINX_VITIS.")
    return xsdb


def find_uart(board):
    pattern = "*FT232R*" if board == "nexys" else "*-if01-port0"
    ports = sorted(glob.glob(os.path.join("/dev/serial/by-id", pattern)))
    if not ports:
        sys.exit(f"No se encuentra la UART de la placa ({pattern} en /dev/serial/by-id): usa --port.")
    return os.path.realpath(ports[0])


def xsdb_script(board, bit, elf):
    """Programa la FPGA (si hay bitstream), carga el ELF y lo arranca."""
    lines = ["connect"]
    if board == "nexys":
        if bit:
            lines += ['targets -set -filter {name =~ "*xc7a200t*"}', f'fpga "{bit}"', "after 1000"]
        lines += ['targets -set -filter {name =~ "*MicroBlaze*#0*"}', "rst -processor"]
    else:
        if bit:
            lines += ['targets -set -nocase -filter {name =~ "*xc7z020*"}', f'fpga -f "{bit}"', "after 500"]
        ps7_init = os.path.join(platform_hw("cvqkd_bob"), "ps7_init.tcl")
        lines += ['targets -set -nocase -filter {name =~ "*Cortex-A9*#0"}', "catch {stop}",
                  "catch {rst -processor}", "after 200", f'source "{ps7_init}"', "ps7_init", "ps7_post_config"]
    lines += [f'dow "{elf}"', "con", "exit"]
    return "\n".join(lines) + "\n"


def open_uart(port, baud):
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
    attrs = termios.tcgetattr(fd)
    speed = {9600: termios.B9600, 115200: termios.B115200}[baud]
    attrs[0] = termios.IGNPAR
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    attrs[4] = attrs[5] = speed
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 10  # readline vuelve tras 1 s sin datos
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)
    return os.fdopen(fd, "r", encoding="utf-8", errors="ignore")


def golden_key_words():
    """Clave de Bob (block_bits.txt: 68 columnas de 384 bits) en las 816 palabras que lee Alice."""
    words = []
    with open(os.path.join(REPO, "cvqkd_matlab", "data", "block_bits.txt")) as f:
        for col in (line.strip() for line in f if line.strip()):
            bits = col[::-1]  # bit 0 de la columna = último carácter
            words += [int(bits[32 * w:32 * w + 32][::-1], 2) for w in range(12)]
    return words


def check_key(received):
    golden = golden_key_words()
    bit_errors = sum(bin(r ^ g).count("1") for r, g in zip(received, golden))
    ok = len(received) == len(golden) and bit_errors == 0
    print(f"\n[CLAVE] {len(received)}/{len(golden)} palabras recibidas, {bit_errors} bits distintos de Bob: "
          + ("COINCIDE" if ok else "NO COINCIDE"))
    return ok


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run", choices=RUNS)
    parser.add_argument("--port", help="puerto serie (por defecto, autodetección)")
    parser.add_argument("--elf", help="ELF a ejecutar")
    parser.add_argument("--bit", help="bitstream a programar")
    parser.add_argument("--no-bit", action="store_true", help="no reprogramar la FPGA")
    parser.add_argument("--timeout", type=int, help="segundos máximos de escucha")
    args = parser.parse_args()

    cfg = RUNS[args.run]
    elf = args.elf or cfg["elf"]
    bit = None if args.no_bit else (args.bit or cfg["bit"])
    for path in filter(None, [elf, bit]):
        if not os.path.exists(path):
            sys.exit(f"No existe {path}")
    port = args.port or find_uart(cfg["board"])
    xsdb = find_xsdb()

    print(f"[UART] {port} a {cfg['baud']} baudios")
    uart = open_uart(port, cfg["baud"])

    with tempfile.NamedTemporaryFile("w", suffix=".tcl", delete=False) as tcl:
        tcl.write(xsdb_script(cfg["board"], bit, elf))
    print(f"[XSDB] {'Programando ' + os.path.basename(bit) + ' y ' if bit else ''}cargando {os.path.basename(elf)}")
    launcher = threading.Thread(target=subprocess.run, args=([xsdb, tcl.name],),
                                kwargs=dict(capture_output=True), daemon=True)
    launcher.start()

    key, in_key, ok = [], False, True
    deadline = time.time() + (args.timeout or cfg["timeout"])
    try:
        while time.time() < deadline:
            line = uart.readline().strip()
            if not line:
                continue
            if line == "--- KEY_START ---":
                in_key, key = True, []
            elif line == "--- KEY_END ---":
                in_key = False
                ok = check_key(key)
            elif in_key:
                key.append(int(line, 16))
                continue
            print(line)
            if cfg["end"] in line:
                time.sleep(0.5)
                print(uart.read(), end="")
                break
        else:
            print(f"\n[AVISO] Tiempo de escucha agotado sin ver '{cfg['end']}'")
            ok = False
    finally:
        uart.close()
        launcher.join(timeout=5)
        os.unlink(tcl.name)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
