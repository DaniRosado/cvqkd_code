#!/usr/bin/env python3
"""
rtl_matching_ldpc_sim.py - Python simulation matching RTL exactly
This implements the exact same algorithm as the RTL:
- Layered min-sum with Z=384, W=16, alpha=0.75
- Same barrel shifter convention
- Same CNU sign accumulation
- Same VNU processing
"""

import re
import os

# Parameters
Z = 384
W = 16
N_ROWS = 46
N_COLS = 68
MAX_ITER = 1
ALPHA = 0.75

def load_bg_rom():
    """Load BG_ROM from RTL package"""
    bg_file = r'C:\Users\usser\TFG\cvqkd_code\cvqkd_alice\rtl\bg_rom_pkg.sv'
    with open(bg_file, 'r') as f:
        content = f.read()
    
    bg_rom = [[-1]*N_COLS for _ in range(N_ROWS)]
    # Extract each row
    rows = re.findall(r"'\{([^}]+)\}", content)
    for r, row_str in enumerate(rows):
        vals = row_str.split(',')
        for c, val in enumerate(vals):
            bg_rom[r][c] = int(val.strip())
    
    print(f"Loaded BG_ROM: {N_ROWS} x {N_COLS}")
    return bg_rom

def load_llr_input():
    """Load test vectors (u_bits.txt)"""
    u_file = r'C:\Users\usser\TFG\cvqkd_code\cvqkd_matlab\data\u_bits.txt'
    llr_input = [[0]*Z for _ in range(N_COLS)]
    
    with open(u_file, 'r') as f:
        for col in range(N_COLS):
            line = f.readline().strip()
            for v in range(Z):
                # 8-bit sign-magnitude: bit 0 = sign, bits 1-7 = magnitude
                sm_sign = int(line[v*8])
                sm_mag = int(line[v*8+1:v*8+8], 2)
                
                # Convert to 16-bit sign-magnitude (same as RTL)
                if sm_sign:
                    llr_input[col][v] = -sm_mag
                else:
                    llr_input[col][v] = sm_mag
    
    print(f"Loaded LLR input: {N_COLS} x {Z}")
    return llr_input

def load_syndrome():
    """Load syndrome"""
    syn_file = r'C:\Users\usser\TFG\cvqkd_code\cvqkd_matlab\data\expected_syndrome.txt'
    syndrome = [[0]*Z for _ in range(N_ROWS)]
    
    with open(syn_file, 'r') as f:
        for r in range(N_ROWS):
            line = f.readline().strip()
            for v in range(Z):
                syndrome[r][v] = int(line[v])
    
    print(f"Loaded syndrome: {N_ROWS} x {Z}")
    return syndrome

def barrel_shift(in_data, shift_val):
    """Barrel shifter: data_out[i] = data_in[(i + shift) % Z]"""
    out = [0] * Z
    for i in range(Z):
        src_idx = (i + shift_val) % Z
        out[i] = in_data[src_idx]
    return out

def cnu_process(q_bus, col_idx, syndrome_bit, prev_min1, prev_min2, prev_min1_idx, prev_total_sign):
    """CNU cell: scaled min-sum with sign accumulation"""
    # Initialize on first column
    if col_idx == 0:
        min1 = 32767  # MAX_MAG for W=16
        min2 = 32767
        min1_idx = 0
        total_sign = syndrome_bit
    else:
        min1 = prev_min1
        min2 = prev_min2
        min1_idx = prev_min1_idx
        total_sign = prev_total_sign
    
    # Process each VNU position
    for i in range(Z):
        q_val = q_bus[i]
        q_sign = 1 if q_val < 0 else 0
        q_mag = abs(q_val)
        
        # Update sign accumulation
        total_sign = (total_sign + q_sign) % 2
        
        # Update min1/min2
        if q_mag < min1:
            min2 = min1
            min1 = q_mag
            min1_idx = i
        elif q_mag < min2:
            min2 = q_mag
    
    # Compute R_new for each VNU position
    r_new = [0] * Z
    for i in range(Z):
        # Select min1 or min2 based on column index
        if col_idx == min1_idx:
            raw_mag = min2
        else:
            raw_mag = min1
        
        # Scaled min-sum: alpha=0.75
        norm_mag = raw_mag - (raw_mag >> 2)
        
        # Sign: total_sign ^ q_sign (extrinsic)
        q_sign = 1 if q_bus[i] < 0 else 0
        r_sign = (total_sign + q_sign) % 2
        
        if r_sign:
            r_new[i] = -norm_mag
        else:
            r_new[i] = norm_mag
    
    return r_new, min1, min2, min1_idx, total_sign

def main():
    print("=== RTL-matching LDPC Simulation ===\n")
    
    # Load data
    BG_ROM = load_bg_rom()
    llr_input = load_llr_input()
    syndrome = load_syndrome()
    
    # Initialize memories (same as RTL)
    # P_mem: initialized with LLR input (column-major)
    P_mem = [[0]*N_COLS for _ in range(Z)]
    for col in range(N_COLS):
        for v in range(Z):
            P_mem[v][col] = llr_input[col][v]
    
    # R_mem: initialized to zeros (same as RTL BRAM default)
    R_mem = [[[0]*N_COLS for _ in range(N_ROWS)] for _ in range(Z)]
    
    # Run RTL-matching simulation
    print("\n=== Running RTL-matching simulation ===")
    
    for iter in range(MAX_ITER):
        print(f"Iteration {iter}")
        
        for row in range(N_ROWS):
            # Get shift value for this row
            shift_val = 0
            for col in range(N_COLS):
                if BG_ROM[row][col] != -1:
                    shift_val = BG_ROM[row][col]
                    break
            
            # Forward shift P_mem and R_mem
            P_shifted = barrel_shift([P_mem[v][row] for v in range(Z)], shift_val)
            R_shifted = [0] * Z
            for col in range(N_COLS):
                if BG_ROM[row][col] != -1:
                    R_col = barrel_shift([R_mem[v][row][col] for v in range(Z)], shift_val)
                    for v in range(Z):
                        R_shifted[v] += R_col[v]
            
            # Process each column
            prev_min1 = 32767
            prev_min2 = 32767
            prev_min1_idx = 0
            prev_total_sign = 0
            
            for col in range(N_COLS):
                if BG_ROM[row][col] == -1:
                    continue
                
                # VNU: Q = P_shifted - R_shifted
                Q_bus = [P_shifted[v] - R_shifted[v] for v in range(Z)]
                
                # CNU: scaled min-sum
                R_new, min1, min2, min1_idx, total_sign = cnu_process(
                    Q_bus, col, syndrome[row][0],
                    prev_min1, prev_min2, prev_min1_idx, prev_total_sign
                )
                
                # VNU: P_new = Q + R_new
                P_new = [Q_bus[v] + R_new[v] for v in range(Z)]
                
                # Inverse shift and write back
                inv_shift = (Z - shift_val) % Z
                P_inv = barrel_shift(P_new, inv_shift)
                R_inv = barrel_shift(R_new, inv_shift)
                
                for v in range(Z):
                    P_mem[v][row] = P_inv[v]
                    R_mem[v][row][col] = R_inv[v]
                
                # Update prev values for next column
                prev_min1 = min1
                prev_min2 = min2
                prev_min1_idx = min1_idx
                prev_total_sign = total_sign
                
                # Trace Row 0, Col 0
                if row == 0 and col == 0:
                    print(f"  Col {col}: shift={shift_val}, P_shifted[0]={P_shifted[0]}, "
                          f"R_shifted[0]={R_shifted[0]}, Q[0]={Q_bus[0]}, R_new[0]={R_new[0]}")
    
    # Compare with RTL R_mem dump
    print("\n=== Comparing with RTL R_mem dump ===")
    rtl_file = r'C:\Users\usser\TFG\cvqkd_code\cvqkd_alice\sim\rtl_r_mem_dump.txt'
    with open(rtl_file, 'r') as f:
        rtl_lines = [line.strip() for line in f.readlines()]
    
    # Parse RTL R_mem
    rtl_r = [[[0]*N_COLS for _ in range(N_ROWS)] for _ in range(Z)]
    idx = 0
    for r in range(N_ROWS):
        for c in range(N_COLS):
            if BG_ROM[r][c] == -1:
                continue
            for v in range(Z-1, -1, -1):
                if idx >= len(rtl_lines):
                    break
                hex_val = int(rtl_lines[idx], 16)
                if hex_val >= 32768:
                    rtl_r[v][r][c] = hex_val - 65536
                else:
                    rtl_r[v][r][c] = hex_val
                idx += 1
    
    # Compare
    total = 0
    match = 0
    sign_match = 0
    for r in range(N_ROWS):
        for c in range(N_COLS):
            if BG_ROM[r][c] == -1:
                continue
            for v in range(Z):
                total += 1
                if R_mem[v][r][c] == rtl_r[v][r][c]:
                    match += 1
                if (R_mem[v][r][c] > 0) == (rtl_r[v][r][c] > 0):
                    sign_match += 1
    
    print(f"Total entries: {total}")
    print(f"Exact match: {match} ({100*match/total:.2f}%)")
    print(f"Sign match: {sign_match} ({100*sign_match/total:.2f}%)")

if __name__ == '__main__':
    main()
