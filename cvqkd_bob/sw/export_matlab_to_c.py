#!/usr/bin/env python3
"""
================================================================================
export_matlab_to_c.py
Convierte los archivos de prueba generados por MATLAB en un fichero de cabecera C
('matlab_vectors.h') para compilarlo directamente en la aplicación de Vitis.
================================================================================
"""

import os
import sys

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Rutas por defecto (soporta tanto Windows como Linux)
    # Si se pasa como argumento, usarlo; si no, buscar en la ruta relativa estándar del repo
    if len(sys.argv) > 1:
        data_dir = sys.argv[1]
    else:
        # Relativo dentro de cvqkd_code: cvqkd_bob/sw/ -> cvqkd_matlab/data/
        data_dir = os.path.normpath(os.path.join(script_dir, "..", "..", "cvqkd_matlab", "data"))

    if not os.path.isdir(data_dir):
        # Fallback a la ruta absoluta de Linux si existe
        linux_path = "/home/drg/TFG/cvqkd_code/cvqkd_matlab/data"
        if os.path.isdir(linux_path):
            data_dir = linux_path
        else:
            print(f"[ERROR] No se encuentra el directorio de datos: {data_dir}")
            print("Uso: python3 export_matlab_to_c.py [ruta_a_cvqkd_matlab/data]")
            sys.exit(1)

    out_file = os.path.join(script_dir, "matlab_vectors.h")
    print(f"[INFO] Leyendo vectores desde: {data_dir}")
    print(f"[INFO] Generando cabecera C en: {out_file}")

    with open(out_file, "w") as out:
        out.write("/* Auto-generado por export_matlab_to_c.py */\n")
        out.write("#ifndef MATLAB_VECTORS_H\n")
        out.write("#define MATLAB_VECTORS_H\n\n")
        out.write("#include <stdint.h>\n\n")

        # 1. BOB RAW ADC (27857 muestras de 32 bits)
        adc_file = os.path.join(data_dir, "bob_raw_adc.txt")
        print("  -> Procesando bob_raw_adc.txt...")
        with open(adc_file, "r") as f:
            lines = [l.strip() for l in f if l.strip()]
        out.write(f"#define VEC_ADC_COUNT {len(lines)}\n")
        out.write("static const uint32_t vec_bob_adc[VEC_ADC_COUNT] = {\n")
        for i, val in enumerate(lines):
            out.write(f"    0x{val}u,\n")
        out.write("};\n\n")

        # 2. ALICE SACRIFICE DATA (13056 muestras de 32 bits)
        alice_file = os.path.join(data_dir, "alice_ram.txt")
        print("  -> Procesando alice_ram.txt...")
        with open(alice_file, "r") as f:
            lines = [l.strip() for l in f if l.strip()]
        out.write(f"#define VEC_ALICE_COUNT {len(lines)}\n")
        out.write("static const uint32_t vec_alice_data[VEC_ALICE_COUNT] = {\n")
        for i, val in enumerate(lines):
            out.write(f"    0x{val}u,\n")
        out.write("};\n\n")

        # 3. MASK BITS (26112 bits empaquetados en 816 palabras de 32 bits)
        mask_file = os.path.join(data_dir, "mask_bit.txt")
        print("  -> Procesando y empaquetando mask_bit.txt...")
        with open(mask_file, "r") as f:
            bits = [int(l.strip()) for l in f if l.strip()]
        
        packed_words = []
        for w in range(0, len(bits), 32):
            word_val = 0
            for b in range(min(32, len(bits) - w)):
                if bits[w + b]:
                    word_val |= (1 << b)
            packed_words.append(word_val)

        out.write(f"#define VEC_MASK_WORDS {len(packed_words)}\n")
        out.write("static const uint32_t vec_mask_packed[VEC_MASK_WORDS] = {\n")
        for w in packed_words:
            out.write(f"    0x{w:08X}u,\n")
        out.write("};\n\n")

        # 4. EXPECTED MDR (3264 bloques de 256 bits = 3264 * 8 palabras de 32 bits)
        mdr_file = os.path.join(data_dir, "expected_m_messages.txt")
        print("  -> Procesando expected_m_messages.txt...")
        with open(mdr_file, "r") as f:
            mdr_lines = [l.strip() for l in f if l.strip()]

        out.write(f"#define VEC_MDR_BLOCKS {len(mdr_lines)}\n")
        out.write(f"#define VEC_MDR_WORDS ({len(mdr_lines)} * 8)\n")
        out.write("static const uint32_t vec_expected_mdr[VEC_MDR_WORDS] = {\n")
        for line in mdr_lines:
            # 64 caracteres hex: 8 palabras de 8 caracteres.
            # En Little-Endian de AXI-Stream, la dimensión 0 son los 8 chars finales
            # pero leídos por slices de 32 bits de derecha a izquierda:
            for i in range(8):
                # i=0: chars 56:64, i=1: chars 48:56, ..., i=7: chars 0:8
                start = 64 - (i + 1) * 8
                end = 64 - i * 8
                word_hex = line[start:end]
                out.write(f"    0x{word_hex}u,")
            out.write("\n")
        out.write("};\n\n")

        # 5. EXPECTED SYNDROME (46 filas de 384 bits padded a 512 bits = 46 * 16 palabras)
        syn_file = os.path.join(data_dir, "expected_syndrome.txt")
        print("  -> Procesando expected_syndrome.txt...")
        with open(syn_file, "r") as f:
            syn_lines = [l.strip() for l in f if l.strip()]

        out.write(f"#define VEC_SYN_ROWS {len(syn_lines)}\n")
        out.write(f"#define VEC_SYN_WORDS ({len(syn_lines)} * 16)\n")
        out.write("static const uint32_t vec_expected_syndrome[VEC_SYN_WORDS] = {\n")
        for line in syn_lines:
            # line tiene 384 caracteres '0'/'1'.
            # Los convertimos en 12 palabras de 32 bits (LSB first por cada 32 bits)
            # y añadimos 4 palabras de 0 para completar los 512 bits (16 palabras de 32b)
            for w in range(12):
                word_val = 0
                for b in range(32):
                    bit_idx = w * 32 + b
                    if bit_idx < len(line) and line[bit_idx] == '1':
                        word_val |= (1 << b)
                out.write(f"    0x{word_val:08X}u,")
            # Padding de 128 bits (4 palabras a 0)
            out.write(" 0x00000000u, 0x00000000u, 0x00000000u, 0x00000000u,\n")
        out.write("};\n\n")

        out.write("#endif /* MATLAB_VECTORS_H */\n")

    print("[EXITO] matlab_vectors.h generado correctamente.")

if __name__ == "__main__":
    main()
