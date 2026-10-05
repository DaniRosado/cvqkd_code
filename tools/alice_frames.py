#!/usr/bin/env python3
"""
Reconcilia en la Nexys Video tramas nuevas de MATLAB, cargadas por JTAG, y compara cada
resultado con la simulación de la RTL.

    tools/alice_frames.py                   # 10 tramas en 8, 10, 11, 11,5, 12, 12,5, 13, 13,5 y 14 km
    tools/alice_frames.py -s 3 10 12        # 3 tramas en 10 y 12 km
    tools/alice_frames.py --generar         # solo genera las tramas (sin placa)
    tools/alice_frames.py --bit <fichero>   # bitstream que se programa (por defecto, el de la
                                            # plataforma de Vitis, como run_board.py)

MATLAB genera cada trama (tb_generador_master.m con CVQKD_SOLO_ALICE=1) en
build/alice_frames/L<km>km_s<semilla>, con las mismas semillas que tools/waterfall_ldpc.sh.
Después xsdb, con el MicroBlaze parado, carga el síndrome y, por las ventanas de carga del
wrapper, X, m y K; lanza MDR + LDPC y lee el estado, los ciclos y la clave. Por trama se
comprueba que:
  - los tres contadores de bloques llegan a 3.264 (la carga ha llegado a las BRAM);
  - si el LDPC converge, la clave coincide con la de Bob;
  - ciclos = 27.561 + 1.094 x iteraciones (884 menos si no converge: no se extrae la clave);
  - la convergencia y las iteraciones son las de la simulación (build/waterfall), si existe.
Resultados en build/alice_frames/placa.csv. MATLAB no se ejecuta como root: si el JTAG
necesita sudo, genera antes las tramas con --generar.
"""

import argparse
import csv
import os
import struct
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

from run_board import REPO, find_xsdb, golden_key_words, platform_hw

OUT = os.path.join(REPO, "build", "alice_frames")
X, M, K, SYN, KEY = ("alice_mdr_inputs.txt", "expected_m_messages.txt", "alice_k_dynamic.txt",
                     "expected_syndrome_words.hex", "block_bits.txt")
BLOCKS = 3264

# Carga y ejecución de una trama desde xsdb (mapa de registros en el wrapper de Alice)
TCL_PROCS = r"""
proc words {f} { set h [open $f rb]; set d [read $h]; close $h; binary scan $d iu* w; return $w }
proc push {addr w n} {
    for {set i 0} {$i < [llength $w]} {incr i $n} { mwr -force $addr [lrange $w $i [expr {$i + $n - 1}]] }
}
proc run_frame {name dir} {
    set B 0x4000
    mwr -force $B 1
    mwr -force $B 0
    mwr -force [expr {$B + 0x0C}] 1
    mwr -force [expr {$B + 0x100}] [words $dir/syn.bin]
    push [expr {$B + 0x1E00}] [words $dir/k.bin] 128
    push [expr {$B + 0x1800}] [words $dir/x.bin] 256
    push [expr {$B + 0x1C00}] [words $dir/m.bin] 128
    set rx [mrd -force -value [expr {$B + 0x10}] 4]
    mwr -force $B 0x0A
    for {set t 0} {$t < 100} {incr t} {
        set st [mrd -force -value [expr {$B + 0x04}]]
        if {($st & 0x2) && !($st & 0x10)} break
        after 10
    }
    set cyc [mrd -force -value [expr {$B + 0x18}]]
    set key [mrd -force -value [expr {$B + 0xA00}] 816]
    puts "FRAME $name $st $cyc [lindex $rx 0] [lindex $rx 1] [lindex $rx 3] $key"
    flush stdout
}
"""


def frame_dir(km, seed):
    return os.path.join(OUT, f"L{km}km_s{seed}")


def generate(km, seed):
    """Vectores de Alice de una trama (si no existen ya) y sus ficheros binarios para xsdb."""
    d = frame_dir(km, seed)
    if not all(os.path.exists(os.path.join(d, f)) for f in (X, M, K, SYN, KEY)):
        os.makedirs(d, exist_ok=True)
        env = dict(os.environ, CVQKD_L_KM=km, CVQKD_SEED=str(seed), CVQKD_SOLO_ALICE="1", CVQKD_DATA_OUT=d)
        script = os.path.join(REPO, "cvqkd_matlab", "scripts", "tb_generador_master.m")
        matlab = subprocess.run([os.environ.get("MATLAB", "matlab"), "-batch", f"run('{script}')"], env=env,
                                capture_output=True, text=True)
        if matlab.returncode != 0:
            sys.exit(f"MATLAB ha fallado en {d}:\n{(matlab.stdout + matlab.stderr)[-500:]}")
        for f in os.listdir(d):
            if f not in (X, M, K, SYN, KEY):
                os.remove(os.path.join(d, f))
    for name, src, per_line in (("x", X, 4), ("m", M, 8), ("k", K, 1), ("syn", SYN, 1)):
        words = []
        with open(os.path.join(d, src)) as f:
            for line in (l.strip() for l in f if l.strip()):
                v = int(line, 16)
                words += [(v >> (32 * w)) & 0xFFFFFFFF for w in range(per_line)]
        with open(os.path.join(d, name + ".bin"), "wb") as f:
            f.write(struct.pack(f"<{len(words)}I", *words))
    return d


def simulation(km, seed):
    """(convergido, iteraciones) de la simulación de la RTL, si tools/waterfall_ldpc.sh la hizo."""
    path = os.path.join(REPO, "build", "waterfall", f"L{km}km_s{seed}", "resultado.csv")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        row = f.read().strip().split(",")
    return row[3] == "1", int(row[4])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-s", type=int, default=10, help="tramas (semillas) por distancia")
    parser.add_argument("km", nargs="*", default=["8", "10", "11", "11.5", "12", "12.5", "13", "13.5", "14"])
    parser.add_argument("--generar", action="store_true", help="solo genera las tramas")
    parser.add_argument("--bit", default=os.path.join(platform_hw("cvqkd_alice"), "design_1_wrapper.bit"))
    args = parser.parse_args()

    frames = [(km, seed) for km in args.km for seed in range(1, args.s + 1)]
    missing = [f for f in frames if not os.path.exists(os.path.join(frame_dir(*f), KEY))]
    if missing and os.geteuid() == 0:
        sys.exit("Faltan tramas por generar y MATLAB no se ejecuta como root: "
                 "lanza antes tools/alice_frames.py --generar sin sudo.")
    print(f"[MATLAB] {len(frames)} tramas ({len(missing)} por generar) en {OUT}")
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda f: generate(*f), frames))
    if args.generar:
        return
    if not os.path.exists(args.bit):
        sys.exit(f"No existe {args.bit}")

    lines = ["connect", 'targets -set -filter {name =~ "*xc7a200t*"}', f'fpga -file "{args.bit}"', "after 1000",
             'targets -set -filter {name =~ "*MicroBlaze*#0*"}', "catch {stop}", TCL_PROCS]
    lines += [f'run_frame {km}:{seed} "{frame_dir(km, seed)}"' for km, seed in frames]
    lines.append("exit")
    with tempfile.NamedTemporaryFile("w", suffix=".tcl", delete=False) as tcl:
        tcl.write("\n".join(lines) + "\n")

    print(f"[XSDB] Programando {os.path.basename(args.bit)} y reconciliando {len(frames)} tramas")
    results, t0 = [], time.time()
    xsdb = subprocess.Popen([find_xsdb(), tcl.name], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in xsdb.stdout:
        if not line.startswith("FRAME "):
            if "rror" in line:
                print(line.rstrip())
            continue
        f = line.split()
        km, seed = f[1].split(":")
        st, cyc, n_x, n_m, n_k = (int(v) for v in f[2:7])
        key = [int(v) for v in f[7:]]
        conv, iters = bool(st & 0x4), (st >> 8) & 0xFF
        key_ok = key == golden_key_words(os.path.join(frame_dir(km, seed), KEY))
        load_ok = n_x == n_m == n_k == BLOCKS
        cyc_ok = cyc == 27561 + 1094 * iters - (0 if conv else 884)   # Sin convergencia no se extrae la clave
        sim = simulation(km, seed)
        sim_ok = sim is None or sim == (conv, iters)
        ok = load_ok and cyc_ok and sim_ok and (key_ok or not conv)
        results.append(dict(distancia_km=km, semilla=seed, convergido=int(conv), iteraciones=iters, ciclos=cyc,
                            clave_correcta=int(conv and key_ok), igual_simulacion="" if sim is None else int(sim_ok),
                            ok=int(ok)))
        estado = (f"converge en {iters} it., clave {'idéntica a la de Bob' if key_ok else 'DISTINTA de la de Bob'}"
                  if conv else f"no converge ({iters} it.)")
        extra = "" if load_ok else f" | CARGA INCOMPLETA (X={n_x}, m={n_m}, K={n_k}: ¿bitstream sin ventanas de carga?)"
        extra += "" if cyc_ok else " | CICLOS FUERA DEL MODELO"
        extra += "" if sim is None else (" | igual que la simulación" if sim_ok else f" | SIMULACIÓN: {sim}")
        print(f"  {km:>4} km, semilla {seed:>2}: {estado}, {cyc} ciclos ({time.time() - t0:.0f} s){extra}")
    xsdb.wait()
    os.unlink(tcl.name)
    if not results:
        sys.exit("xsdb no ha devuelto ninguna trama")

    with open(os.path.join(OUT, "placa.csv"), "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)

    print("-" * 70)
    print(f"{'km':>5} {'reconciliadas':>14} {'iguales a la simulación':>24}")
    for km in args.km:
        r = [x for x in results if x["distancia_km"] == km]
        print(f"{km:>5} {sum(x['clave_correcta'] for x in r):>8}/{len(r):<5} "
              f"{sum(x['igual_simulacion'] == 1 for x in r):>16}/{sum(x['igual_simulacion'] != '' for x in r)}")
    bad = [x for x in results if not x["ok"]]
    print(f"Tramas correctas: {len(results) - len(bad)}/{len(results)} (detalle en {OUT}/placa.csv)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
