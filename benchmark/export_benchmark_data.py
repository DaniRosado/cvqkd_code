#!/usr/bin/env python3
"""
Regenera los vectores de cvqkd_benchmark_data.h con la trama actual de MATLAB
(cvqkd_matlab/data), la misma que reconcilia la FPGA de Alice: entradas del MDR (X de
Alice, mensajes m de Bob y factor K), síndrome y clave de Bob. Las tablas del código
(BG_ROW_DEG y BG_EDGES) no se tocan.

    benchmark/export_benchmark_data.py
"""

import os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "cvqkd_matlab", "data")
HEADER = os.path.join(HERE, "cvqkd_benchmark_data.h")


def lines(name):
    with open(os.path.join(DATA, name)) as f:
        return [l.strip() for l in f if l.strip()]


def c_array(decl, values, fmt, per_line):
    rows = [", ".join(fmt(v) for v in values[i:i + per_line]) for i in range(0, len(values), per_line)]
    return decl + " = {\n" + "".join(f"    {r},\n" for r in rows) + "};\n"


# Síndrome: 46 filas x 12 palabras, tal como lo carga el acelerador
syn = [int(l, 16) for l in lines("expected_syndrome_words.hex")]

# Clave de Bob: 68 columnas de 384 bits (bit 0 = último carácter) -> 816 palabras
key = []
for col in lines("block_bits.txt"):
    bits = col[::-1]
    key += [int(bits[32 * w:32 * w + 32][::-1], 2) for w in range(12)]



def fields(name, bits, count):
    """Cada línea es un vector de 'count' enteros con signo de 'bits' bits (el primero, en los bits bajos)."""
    out = []
    for v in (int(l, 16) for l in lines(name)):
        for i in range(count):
            f = (v >> (bits * i)) & ((1 << bits) - 1)
            out.append(f - (1 << bits) if f >> (bits - 1) else f)
    return out


# Entradas del MDR, como las lee el acelerador de sus BRAM: 3.264 bloques de 8 dimensiones
x = fields("alice_mdr_inputs.txt", 16, 8)
m = fields("expected_m_messages.txt", 32, 8)
k = fields("alice_k_dynamic.txt", 32, 1)

assert (len(syn), len(key), len(x), len(m), len(k)) == (552, 816, 26112, 26112, 3264)

with open(HEADER) as f:
    head = f.read().split("static const uint32_t GOLDEN_SYN_WORDS")[0]

with open(HEADER, "w") as f:
    f.write(head)
    f.write(c_array("static const uint32_t GOLDEN_SYN_WORDS[N_SYN_WORDS]", syn, lambda v: f"0x{v:08X}u", 8))
    f.write("\n")
    f.write(c_array("static const uint32_t GOLDEN_KEY_WORDS[N_KEY_WORDS]", key, lambda v: f"0x{v:08X}u", 8))
    f.write("\n")
    f.write(c_array("static const int16_t MDR_X[N_CODE_BITS]", x, lambda v: f"{v:5d}", 16))
    f.write("\n")
    f.write(c_array("static const int32_t MDR_M[N_CODE_BITS]", m, lambda v: f"{v:9d}", 8))
    f.write("\n")
    f.write(c_array("static const int32_t MDR_K[N_CODE_BITS / 8]", k, lambda v: f"{v:3d}", 16))
    f.write("\n#endif /* CVQKD_BENCHMARK_DATA_H */\n")

print(f"{HEADER}: {len(k)} bloques del MDR, {len(syn)} palabras de síndrome y {len(key)} de clave")
