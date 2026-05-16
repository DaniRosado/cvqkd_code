#!/usr/bin/env python3
"""Generate LUT-based expected LLR values matching RTL behavior."""

import math

RECIP_LUT = [int(round(2**31 * 256 / (256 + i))) for i in range(256)]
RECIP_LUT[0] = 0x7FFFFFFF

def reciprocal_lut(norm_val):
    if norm_val == 0:
        return 0x7FFFFFFF
    leading = norm_val.bit_length() - 1
    shift_amt = 16 - leading
    shift_amt = 16 - leading
    # Match RTL: shift_amt is 5-bit unsigned; negative → large → 0
    if shift_amt >= 0:
        norm_shifted = norm_val << shift_amt
    else:
        norm_shifted = 0  # RTL: 18-bit << (5-bit wrap) = 0
    norm_shifted = norm_shifted & 0x3FFFF
    lut_addr = (norm_shifted >> 8) & 0xFF
    lut_val = RECIP_LUT[lut_addr]
    scale = 16 - shift_amt
    if scale >= 0:
        recip = lut_val >> scale
    else:
        recip = lut_val << (-scale)
    if recip > 0x7FFFFFFF:
        recip = 0x7FFFFFFF
    return recip

def sext16(v):
    """Sign-extend 16-bit to Python int"""
    return v if v < 2**15 else v - 2**16

def q31_to_float(v):
    """Convert Q1.31 signed int to float"""
    if v >= 2**31:
        v -= 2**32
    return v / 2**31

def float_to_q31(f):
    """Convert float to Q1.31 signed int"""
    v = int(round(f * 2**31))
    if v >= 2**31:
        v = 2**31 - 1
    elif v < -2**31:
        v = -2**31
    return v

def q31_mul(a, b):
    """Q1.31 × Q1.31 → Q1.31 (matching q31_mul in RTL).
    Both a and b are unsigned 32-bit Q1.31 values (RTL uses signed logic).
    """
    # Convert from unsigned 32-bit to signed Python int
    if a >= 2**31:
        a -= 2**32
    if b >= 2**31:
        b -= 2**32
    p = a * b  # Q2.62 (Python arbitrary precision)
    shifted = p >> 31  # arithmetic shift → Q1.31
    if shifted > 0x7FFFFFFF:
        return 0x7FFFFFFF
    elif shifted < -0x80000000:
        return 0x80000000
    else:
        return shifted & 0xFFFFFFFF

def normalize_8d(v):
    """Normalize 8D vector using LUT reciprocal (matches normalize_8d.sv).
    v: list of 8 signed 16-bit integers
    returns: list of 8 Q1.31 values
    """
    # Compute sum of squares (same as norm_8d.sv: unsigned 32-bit squares)
    sum_sq = 0
    for x in v:
        x_u32 = abs(x)  # square of signed 16-bit fits in uint32
        sq = x * x
        sum_sq += sq
    # norm = sqrt(sum_sq) (same sqrt_approx as norm_8d.sv)
    norm_val = sqrt_approx(sum_sq)
    # Look up reciprocal
    recip = reciprocal_lut(norm_val)
    # Multiply each component by reciprocal
    # n_i = (x_i * recip_q31) lower 32 bits of 48-bit product
    result = []
    for x in v:
        p = x * recip  # 16-bit × 32-bit = 48-bit signed
        n = p & 0xFFFFFFFF  # lower 32 bits
        result.append(n)
    return result, norm_val

def sqrt_approx(val):
    """Replicate norm_8d.sv sqrt_approx function"""
    rem = val
    root = 0
    for i in range(16, -1, -1):
        div = (root << 1) + (1 << i)
        if rem >= (div << i):
            rem = rem - (div << i)
            root = root + (1 << i)
    return root & 0x3FFFF  # 18-bit result

def gen_orthogonal_matrix(v):
    """Replicate generar_matriz_ortogonal (same generate_orthogonal_matrix in mat_vec_mul_8x8)
    v: list of 8 Q1.31 values
    returns: 8×8 matrix of Q1.31 values
    """
    [v1, v2, v3, v4, v5, v6, v7, v8] = v
    M = [
        [ v1,  v2,  v3,  v4,  v5,  v6,  v7,  v8],
        [-v2 & 0xFFFFFFFF,  v1, -v4 & 0xFFFFFFFF,  v3, -v6 & 0xFFFFFFFF,  v5,  v8, -v7 & 0xFFFFFFFF],
        [-v3 & 0xFFFFFFFF,  v4,  v1, -v2 & 0xFFFFFFFF, -v7 & 0xFFFFFFFF, -v8 & 0xFFFFFFFF,  v5,  v6],
        [-v4 & 0xFFFFFFFF, -v3 & 0xFFFFFFFF,  v2,  v1, -v8 & 0xFFFFFFFF,  v7, -v6 & 0xFFFFFFFF,  v5],
        [-v5 & 0xFFFFFFFF,  v6,  v7,  v8,  v1, -v2 & 0xFFFFFFFF, -v3 & 0xFFFFFFFF, -v4 & 0xFFFFFFFF],
        [-v6 & 0xFFFFFFFF, -v5 & 0xFFFFFFFF,  v8, -v7 & 0xFFFFFFFF,  v2,  v1,  v4, -v3 & 0xFFFFFFFF],
        [-v7 & 0xFFFFFFFF, -v8 & 0xFFFFFFFF, -v5 & 0xFFFFFFFF,  v6,  v3, -v4 & 0xFFFFFFFF,  v1,  v2],
        [-v8 & 0xFFFFFFFF,  v7, -v6 & 0xFFFFFFFF, -v5 & 0xFFFFFFFF,  v4,  v3, -v2 & 0xFFFFFFFF,  v1],
    ]
    # Ensure all values are unsigned 32-bit
    for i in range(8):
        for j in range(8):
            M[i][j] = M[i][j] & 0xFFFFFFFF
    return M

def mat_vec_mul_q31(M, vec):
    """Q1.31 matrix-vector multiply (matching mat_vec_mul_8x8.sv).
    M: 8×8 matrix of Q1.31 values
    vec: list of 8 Q1.31 values
    returns: list of 8 Q1.31 values
    """
    result = []
    for i in range(8):
        acc = 0
        for j in range(8):
            a = M[i][j]
            if a >= 2**31:
                a -= 2**32
            b = vec[j]
            if b >= 2**31:
                b -= 2**32
            prod = a * b  # Q2.62
            acc += prod >> 3  # pre-shift by 3 to avoid 64-bit overflow
        # Shift right 28 (total shift = 28 + 3 = 31)
        shifted = acc >> 28
        if shifted > 0x7FFFFFFF:
            shifted = 0x7FFFFFFF
        elif shifted < -0x80000000:
            shifted = -0x80000000
        else:
            shifted = shifted & 0xFFFFFFFF
        result.append(shifted)
    return result

# ── Main ──
def main():
    # Read Alice key data (packed {Q[15:0], P[15:0]})
    with open('/home/drg/TFG/code/cvqkd_matlab/data/alice_key_data.txt') as f:
        alice_hex = [int(v.strip(), 16) for v in f]
    alice_p = [sext16(v & 0xFFFF) for v in alice_hex]
    alice_q = [sext16((v >> 16) & 0xFFFF) for v in alice_hex]
    num_symbols = len(alice_p)
    num_blocks = num_symbols // 4
    print(f"Alice: {num_symbols} symbols, {num_blocks} blocks")

    # Read expected LUT-based m values
    with open('/home/drg/TFG/code/cvqkd_matlab/data/expected_m_messages.txt') as f:
        m_hex = [int(v.strip(), 16) for v in f]
    m_q31 = m_hex  # already unsigned 32-bit Q1.31

    # Compute K_llr from expected_llr_math.txt
    with open('/home/drg/TFG/code/cvqkd_matlab/data/expected_llr_math.txt') as f:
        sqrt_T_fp = int(f.readline(), 16)  # line 2
        _ = int(f.readline(), 16) if False else None  # skip line 1
    with open('/home/drg/TFG/code/cvqkd_matlab/data/expected_llr_math.txt') as f:
        lines = f.read().strip().split()
    T_fp = int(lines[0], 16)
    sqrt_T_fp = int(lines[1], 16)
    sigma_sq_fp = int(lines[2], 16)
    
    # K_llr = 2 * sqrt(T*eta) / sigma_sq^2 (in float)
    # sqrt_T_fp is Q16.16, sigma_sq_fp is integer
    K_llr_float = 2 * sqrt_T_fp / (sigma_sq_fp * 65536)
    K_llr_q31 = float_to_q31(K_llr_float)
    print(f"K_llr = {K_llr_float:.10f} (Q1.31: 0x{K_llr_q31 & 0xFFFFFFFF:08X} = {K_llr_q31})")

    # Process each block
    expected_llr = []
    mismatch_count = 0
    for blk in range(num_blocks):
        # Build 8D vector: [P0, Q0, P1, Q1, P2, Q2, P3, Q3]
        s = blk * 4
        v = [alice_p[s+0], alice_q[s+0], alice_p[s+1], alice_q[s+1],
             alice_p[s+2], alice_q[s+2], alice_p[s+3], alice_q[s+3]]

        # Normalize using LUT (same as RTL)
        n, norm_val = normalize_8d(v)

        # Build orthogonal matrix M_X from normalized values
        M = gen_orthogonal_matrix(n)

        # Get m values for this block (from LUT-based expected_m_messages.txt)
        m_blk = m_q31[blk*8:(blk+1)*8]

        # Compute U' = M × m
        U = mat_vec_mul_q31(M, m_blk)

        # Compute LLR = K_llr × U'
        for dim in range(8):
            llr = q31_mul(K_llr_q31, U[dim])
            expected_llr.append(llr)

        if blk < 4:
            print(f"\nBlock {blk}:")
            print(f"  raw: {v}")
            print(f"  norm: {norm_val}")
            print(f"  n: {[hex(x) for x in n]}")
            print(f"  m: {[hex(x) for x in m_blk]}")
            for dim in range(8):
                U_float = q31_to_float(U[dim])
                llr_float = q31_to_float(expected_llr[blk*8+dim])
                print(f"  dim{dim}: U'={hex(U[dim])} ({U_float:.6f})  LLR={hex(expected_llr[blk*8+dim])} ({llr_float:.8f})")

    # Compare with MATLAB float expected LLR
    with open('/home/drg/TFG/code/cvqkd_matlab/data/expected_llr_results.txt') as f:
        ref_llr_hex = [int(v.strip(), 16) for v in f]

    print(f"\n=== Comparison with MATLAB float LLR ===")
    max_diff = 0
    max_diff_idx = 0
    matches = 0
    for i in range(len(expected_llr)):
        lut_q31 = expected_llr[i]
        ref_q31 = ref_llr_hex[i]
        diff = abs(lut_q31 - ref_q31)
        if diff > max_diff:
            max_diff = diff
            max_diff_idx = i
        if lut_q31 == ref_q31:
            matches += 1
        elif i < 32:
            lut_s = lut_q31 if lut_q31 < 2**31 else lut_q31 - 2**32
            ref_s = ref_q31 if ref_q31 < 2**31 else ref_q31 - 2**32
            print(f"  idx {i}: LUT=0x{lut_q31:08X} ({lut_s:8d}) REF=0x{ref_q31:08X} ({ref_s:8d}) diff={diff}")

    total = len(expected_llr)
    print(f"\nResults: {matches}/{total} exact matches ({100*matches/total:.1f}%)")
    print(f"Max diff at idx {max_diff_idx}: diff={max_diff}")
    print(f"Max diff as % of ref: {max_diff / ref_llr_hex[max_diff_idx] * 100:.2f}%")

    # Write expected LLR file
    with open('/home/drg/TFG/code/cvqkd_matlab/data/expected_llr_lut.txt', 'w') as f:
        for v in expected_llr:
            f.write(f'{v:08X}\n')
    print(f"\nWritten expected_llr_lut.txt ({len(expected_llr)} values)")

if __name__ == '__main__':
    main()
