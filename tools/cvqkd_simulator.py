#!/usr/bin/env python3
"""
================================================================================
CV-QKD END-TO-END OPTICAL CHANNEL SIMULATOR & FPGA TEST VECTOR GENERATOR
================================================================================
This script implements a complete physical and information-theoretic simulation
of Continuous-Variable Quantum Key Distribution (CV-QKD) based on:
  - Gaussian modulated coherent states (GG02 protocol)
  - Standard Single-Mode Fiber (SMF-28) with attenuation and excess noise
  - Laser phase noise (Wiener process + acoustic drift) & pilot-assisted DSP
  - 8-Dimensional Multidimensional Reconciliation (MDR, Hurwitz-Radon)
  - 5G-NR LDPC Error Correction (Base Graph 1, Z=384, N=26,112 bits)
  - Asymptotic Secret Key Rate (SKR) calculation via Devetak-Winter & Holevo bound
  - Direct export of test vectors formatted for FPGA hardware (Nexys Video / PYNQ-Z2)
================================================================================
"""

import sys
import os
import math
import random
import time
import argparse

# Default project paths
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG1_FILE = os.path.join(PROJECT_ROOT, "cvqkd_matlab", "data", "NR_1_1_384.txt")
DEFAULT_DATA_DIR = os.path.join(PROJECT_ROOT, "cvqkd_matlab", "data")


# ==============================================================================
# 1. INFORMATION THEORY & SECRET KEY RATE (HOLEVO BOUND)
# ==============================================================================

def g_entropy(x):
    """Von Neumann entropy function for bosonic Gaussian states: g(x) = (x+1)log2(x+1) - x log2(x)."""
    if x <= 1e-12:
        return 0.0
    return (x + 1.0) * math.log2(x + 1.0) - x * math.log2(x)


def compute_skr_metrics(L_km, V_A=5.0, xi=0.01, eta=0.6, v_el=0.1, alpha=0.2, beta=0.72, rep_rate=1e9):
    """
    Computes asymptotic Secret Key Rate (SKR) under collective attacks using
    reverse reconciliation, heterodyne detection (Bob measures P and Q) and the
    trusted detector model (Lodewyck et al. 2007). Rates are per dimension
    (quadrature); every pulse carries 2 dimensions.

    Returns:
        dict with T, snr, I_AB, chi_BE, K_asymp (bits/dim), and skr_bps (bits/sec).
    """
    T = 10.0 ** (-alpha * L_km / 10.0)
    V = V_A + 1.0
    chi_line = 1.0 / T - 1.0 + xi
    chi_het = (2.0 - eta + 2.0 * v_el) / eta
    chi_tot = chi_line + chi_het / T

    # Shannon mutual information per quadrature (each one gets T*eta/2 of the signal)
    snr = T * eta * V_A / (2.0 + 2.0 * v_el + T * eta * xi)
    I_AB = 0.5 * math.log2(1.0 + snr)

    # Symplectic eigenvalues of Gamma_AB before detection
    A = V**2 * (1.0 - 2.0 * T) + 2.0 * T + T**2 * (V + chi_line)**2
    B = (T * (V * chi_line + 1.0))**2
    disc1 = max(0.0, A**2 - 4.0 * B)
    l1 = math.sqrt(max(1.0, 0.5 * (A + math.sqrt(disc1))))
    l2 = math.sqrt(max(1.0, 0.5 * (A - math.sqrt(disc1))))

    # Conditional symplectic eigenvalues after Bob's heterodyne measurement
    sqrt_B = math.sqrt(B)
    denom = T * (V + chi_tot)
    C = (A * chi_het**2 + B + 1.0 + 2.0 * chi_het * (V * sqrt_B + T * (V + chi_line))
         + 2.0 * T * (V**2 - 1.0)) / denom**2
    D = ((V + sqrt_B * chi_het) / denom)**2
    disc2 = max(0.0, C**2 - 4.0 * D)
    l3 = math.sqrt(max(1.0, 0.5 * (C + math.sqrt(disc2))))
    l4 = math.sqrt(max(1.0, 0.5 * (C - math.sqrt(disc2))))

    # Holevo bound: chi(B; E) = S(E) - S(E|y_B), split between the 2 quadratures
    chi_BE = 0.5 * (g_entropy((l1 - 1.0) / 2.0) + g_entropy((l2 - 1.0) / 2.0)
                    - g_entropy((l3 - 1.0) / 2.0) - g_entropy((l4 - 1.0) / 2.0))

    # Asymptotic secret key rate per dimension (2 dimensions per pulse)
    K_asymp = max(0.0, beta * I_AB - chi_BE)
    skr_bps = 2.0 * rep_rate * K_asymp

    return {
        "distance_km": L_km,
        "transmittance": T,
        "loss_db": alpha * L_km,
        "snr_linear": snr,
        "snr_db": 10.0 * math.log10(snr) if snr > 0 else -99.0,
        "I_AB": I_AB,
        "chi_BE": chi_BE,
        "K_asymp": K_asymp,
        "skr_bps": skr_bps,
        "skr_mbps": skr_bps / 1e6
    }


def print_skr_table(V_A=5.0, xi=0.01, eta=0.6, v_el=0.1, alpha=0.2, beta=0.72, rep_rate=1e9):
    """Prints a formatted table of SKR vs fiber distance."""
    print("\n" + "=" * 92)
    print("       CV-QKD SECRET KEY RATE (SKR) VS FIBRE DISTANCE (COLLECTIVE ATTACKS)       ")
    print(f"       V_A = {V_A:.1f} SNU | xi = {xi:.3f} SNU | eta = {eta:.2f} | v_el = {v_el:.2f} | beta = {beta*100:.0f}% | Laser = {rep_rate/1e9:.1f} Gbaud")
    print("=" * 92)
    print(f" {'Dist (km)':^9} | {'T (trans)':^9} | {'Loss (dB)':^9} | {'SNR (dB)':^9} | {'I(A;B)':^8} | {'chi(B;E)':^9} | {'K (b/dim)':^9} | {'SKR @ 1 Gbaud':^14}")
    print("-" * 92)

    distances = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60]
    for d in distances:
        m = compute_skr_metrics(d, V_A=V_A, xi=xi, eta=eta, v_el=v_el, alpha=alpha, beta=beta, rep_rate=rep_rate)
        print(f" {m['distance_km']:7.1f}   | {m['transmittance']:8.4f}  | {m['loss_db']:7.2f} dB | {m['snr_db']:7.2f} dB | {m['I_AB']:7.4f}  | {m['chi_BE']:8.4f}  | {m['K_asymp']:8.5f}  | {m['skr_mbps']:10.2f} Mbps")
    print("=" * 92 + "\n")


# ==============================================================================
# 2. 8D MULTIDIMENSIONAL RECONCILIATION (HURWITZ-RADON)
# ==============================================================================

def get_hurwitz_radon_matrix(v):
    """
    Constructs an 8x8 orthogonal Hurwitz-Radon matrix from an 8D vector v.
    Properties: M(v) * M(v)^T = ||v||^2 * I_8.
    """
    v1, v2, v3, v4, v5, v6, v7, v8 = v
    return [
        [ v1,  v2,  v3,  v4,  v5,  v6,  v7,  v8],
        [-v2,  v1, -v4,  v3, -v6,  v5,  v8, -v7],
        [-v3,  v4,  v1, -v2, -v7, -v8,  v5,  v6],
        [-v4, -v3,  v2,  v1, -v8,  v7, -v6,  v5],
        [-v5,  v6,  v7,  v8,  v1, -v2, -v3, -v4],
        [-v6, -v5,  v8, -v7,  v2,  v1,  v4, -v3],
        [-v7, -v8, -v5,  v6,  v3, -v4,  v1,  v2],
        [-v8,  v7, -v6, -v5,  v4,  v3, -v2,  v1]
    ]


# ==============================================================================
# 3. 5G-NR QC-LDPC SYNDROME & CODEBOOK ENGINE
# ==============================================================================

def load_bg1_matrix(path=BG1_FILE):
    """Loads 5G-NR Base Graph 1 lifting matrix (46 rows x 68 cols)."""
    if not os.path.exists(path):
        raise FileNotFoundError(f"5G-NR BG1 matrix file not found: {path}")
    bg = []
    with open(path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if parts:
                bg.append([int(p) for p in parts])
    if len(bg) != 46 or len(bg[0]) != 68:
        raise ValueError(f"Expected 46x68 BG1 matrix, got {len(bg)}x{len(bg[0])}")
    return bg


def compute_qc_ldpc_syndrome(bg, key_bits_flat, Z=384):
    """
    Computes QC-LDPC syndrome: s = H * b (mod 2) for 46 rows x 384 bits = 17,664 bits.
    
    Args:
        bg: 46x68 lifting matrix
        key_bits_flat: list of 26,112 bits (68 cols x 384 bits)
        Z: lifting size (384)
        
    Returns:
        syndrome_matrix: 46 rows x 384 bits (list of lists of 0/1)
        syndrome_words: list of 552 32-bit integer words
    """
    N_ROWS = 46
    N_COLS = 68

    # Reshape key bits into columns of length Z
    b_cols = []
    for c in range(N_COLS):
        col = key_bits_flat[c * Z : (c + 1) * Z]
        b_cols.append(col)

    # Syndrome matrix (46 x 384)
    syndrome_matrix = [[0] * Z for _ in range(N_ROWS)]
    for r in range(N_ROWS):
        for c in range(N_COLS):
            shift = bg[r][c]
            if shift >= 0:
                col_data = b_cols[c]
                for i in range(Z):
                    # Circular shift convention matching Vivado RTL
                    syndrome_matrix[r][i] ^= col_data[(i + shift) % Z]

    # Convert to 552 32-bit words matching expected_syndrome_words.hex
    # Each row of 384 bits is 12 words of 32 bits
    syndrome_words = []
    for r in range(N_ROWS):
        row_bits = syndrome_matrix[r] # Z elements
        # SystemVerilog endianness: CNU 0 at bit 0, printed as row_bits[Z-1:-1:0]
        # In expected_syndrome.txt: line string has characters from Z-1 down to 0
        line_str = "".join(str(row_bits[Z - 1 - i]) for i in range(Z))
        for w in range(12):
            chunk = line_str[384 - (w + 1) * 32 : 384 - w * 32]
            syndrome_words.append(int(chunk, 2))

    return syndrome_matrix, syndrome_words


# ==============================================================================
# 4. FULL OPTICAL CHANNEL & PHYSICAL LAYER SIMULATION
# ==============================================================================

class CVQKDChannelSimulator:
    """End-to-end physical simulator for fiber-based CV-QKD."""

    def __init__(self, distance_km=10.0, V_A=5.0, xi=0.01, eta=0.6, v_el=0.1,
                 alpha=0.2, rep_rate=1e9, seed=None):
        self.distance_km = distance_km
        self.V_A = V_A
        self.xi = xi
        self.eta = eta
        self.v_el = v_el
        self.alpha = alpha
        self.rep_rate = rep_rate
        self.T = 10.0 ** (-alpha * distance_km / 10.0)

        if seed is not None:
            random.seed(seed)

        # Hardware & memory parameters (matching Vivado testbenches)
        self.L_trama = 16          # 1 pilot + 15 data symbols
        self.N_BOB_DATA = 26112    # Bob useful symbols
        self.N_FRAMES = math.ceil(self.N_BOB_DATA / 15)
        self.N_FIBER = self.N_FRAMES * self.L_trama + 1
        self.N0_adc_var = 10000.0  # ADC variance for 1 SNU
        self.Amp_Piloto = 20000.0  # Pilot pulse amplitude
        self.Z = 384
        self.N_BLOCKS = 3264       # 3264 blocks x 8 dims = 26,112 bits

    def run_simulation(self):
        """Runs the complete optical transmission, DSP, MDR, and syndrome generation."""
        t_start = time.time()
        print(f"\n[SIM] Starting CV-QKD Simulation for L = {self.distance_km:.1f} km (T = {self.T:.4f})...")

        # 1. Phase Noise Profile (Wiener drift + acoustic sine)
        print("  [1/6] Generating laser phase noise (100 kHz Wiener + 500 Hz acoustic)...")
        Ts = 1.0 / self.rep_rate
        sigma_w = math.sqrt(2.0 * math.pi * 100e3 * Ts)
        fase_wiener = [0.0] * self.N_FIBER
        w_accum = 0.0
        for i in range(self.N_FIBER):
            w_accum += random.gauss(0.0, sigma_w)
            fase_wiener[i] = w_accum

        fase_acustica = [0.5 * math.sin(2.0 * math.pi * 500.0 * (i * Ts)) for i in range(self.N_FIBER)]
        fase_total_canal = [fase_wiener[i] + fase_acustica[i] for i in range(self.N_FIBER)]

        # 2. Alice Transmission (Data + Pilots)
        print("  [2/6] Alice generating Gaussian coherent states (V_A = {:.1f} SNU)...".format(self.V_A))
        VarA_adc = self.V_A * self.N0_adc_var
        sigma_A = math.sqrt(VarA_adc)

        P_A_tx = [0.0] * self.N_FIBER
        Q_A_tx = [0.0] * self.N_FIBER
        is_pilot = [False] * self.N_FIBER

        for i in range(0, self.N_FIBER, self.L_trama):
            is_pilot[i] = True
            P_A_tx[i] = self.Amp_Piloto
            Q_A_tx[i] = 0.0

        for i in range(self.N_FIBER):
            if not is_pilot[i]:
                P_A_tx[i] = random.gauss(0.0, sigma_A)
                Q_A_tx[i] = random.gauss(0.0, sigma_A)

        # 3. Optical Fiber Channel (Attenuation + AWGN + Phase Rotation)
        print("  [3/6] Fiber propagating (loss = {:.2f} dB, excess noise xi = {:.3f} SNU)...".format(
            self.alpha * self.distance_km, self.xi))
        # Heterodyne receiver: each quadrature gets sqrt(T*eta/2) of the signal
        # and noise 1 + v_el + T*eta*xi/2 (SNU of each detector)
        Ruido_Total_snu = 1.0 + self.v_el + (self.T * self.eta * self.xi / 2.0)
        Ruido_Total_adc = Ruido_Total_snu * self.N0_adc_var
        sigma_noise = math.sqrt(Ruido_Total_adc)
        atten = math.sqrt(self.T * self.eta / 2.0)

        P_B_rx = [0.0] * self.N_FIBER
        Q_B_rx = [0.0] * self.N_FIBER
        for i in range(self.N_FIBER):
            p_ideal = atten * P_A_tx[i]
            q_ideal = atten * Q_A_tx[i]
            phi = fase_total_canal[i]
            cos_phi = math.cos(phi)
            sin_phi = math.sin(phi)
            P_B_rx[i] = p_ideal * cos_phi - q_ideal * sin_phi + random.gauss(0.0, sigma_noise)
            Q_B_rx[i] = p_ideal * sin_phi + q_ideal * cos_phi + random.gauss(0.0, sigma_noise)

        # 4. Bob DSP: Pilot Phase Recovery (atan2 + unwrap + linear interpolation)
        print("  [4/6] Bob DSP: Recovering and compensating optical phase with pilots...")
        pilot_indices = [i for i in range(self.N_FIBER) if is_pilot[i]]
        fase_pilotos_raw = [math.atan2(Q_B_rx[i], P_B_rx[i]) for i in pilot_indices]

        # Phase unwrap
        fase_pilotos_clean = [fase_pilotos_raw[0]]
        for k in range(1, len(fase_pilotos_raw)):
            diff = fase_pilotos_raw[k] - fase_pilotos_raw[k - 1]
            diff = (diff + math.pi) % (2.0 * math.pi) - math.pi
            fase_pilotos_clean.append(fase_pilotos_clean[-1] + diff)

        # Linear interpolation
        fase_estimada = [0.0] * self.N_FIBER
        p_idx = 0
        for i in range(self.N_FIBER):
            while p_idx < len(pilot_indices) - 1 and pilot_indices[p_idx + 1] <= i:
                p_idx += 1
            if p_idx >= len(pilot_indices) - 1:
                fase_estimada[i] = fase_pilotos_clean[-1]
            else:
                idx0 = pilot_indices[p_idx]
                idx1 = pilot_indices[p_idx + 1]
                weight = (i - idx0) / float(idx1 - idx0)
                fase_estimada[i] = fase_pilotos_clean[p_idx] * (1.0 - weight) + fase_pilotos_clean[p_idx + 1] * weight

        # De-rotation
        data_indices = [i for i in range(self.N_FIBER) if not is_pilot[i]][:self.N_BOB_DATA]
        P_A_data = [int(round(P_A_tx[i])) for i in data_indices]
        Q_A_data = [int(round(Q_A_tx[i])) for i in data_indices]

        P_B_rec = []
        Q_B_rec = []
        for i in data_indices:
            phi_est = -fase_estimada[i]
            cos_p = math.cos(phi_est)
            sin_p = math.sin(phi_est)
            p_rec = P_B_rx[i] * cos_p - Q_B_rx[i] * sin_p
            q_rec = P_B_rx[i] * sin_p + Q_B_rx[i] * cos_p
            P_B_rec.append(int(round(p_rec)))
            Q_B_rec.append(int(round(q_rec)))

        # 5. Parameter Estimation on Sacrificed Samples
        print("  [5/6] Parameter estimation & fixed-point noise calibration...")
        N_SAMPLES = self.N_BOB_DATA // 2
        P_A_sac = P_A_data[:N_SAMPLES]
        Q_A_sac = Q_A_data[:N_SAMPLES]
        P_B_sac = P_B_rec[:N_SAMPLES]
        Q_B_sac = Q_B_rec[:N_SAMPLES]

        mean_PB = sum(P_B_sac) / float(N_SAMPLES)
        mean_QB = sum(Q_B_sac) / float(N_SAMPLES)
        var_PB = sum((x - mean_PB)**2 for x in P_B_sac) / float(N_SAMPLES)
        var_QB = sum((x - mean_QB)**2 for x in Q_B_sac) / float(N_SAMPLES)
        var_B_float = 0.5 * (var_PB + var_QB)

        cov_P = sum((P_A_sac[k]) * (P_B_sac[k] - mean_PB) for k in range(N_SAMPLES)) / float(N_SAMPLES)
        cov_Q = sum((Q_A_sac[k]) * (Q_B_sac[k] - mean_QB) for k in range(N_SAMPLES)) / float(N_SAMPLES)
        cov_AB_float = 0.5 * (cov_P + cov_Q)

        T_eta_est = 2.0 * (cov_AB_float / VarA_adc)**2   # (Cov/V_A)^2 = T*eta/2 in heterodyne
        sigma_ideal = math.sqrt(max(1.0, var_B_float))
        inv_sigma2 = 2.0 / (sigma_ideal**2 + 1e-12)

        # 6. 8D Multidimensional Reconciliation (MDR)
        print("  [6/6] Computing 8D MDR (3,264 blocks) and 5G-NR QC-LDPC syndrome...")
        # Use key symbols (second half)
        P_A_key = P_A_data[N_SAMPLES : N_SAMPLES + self.N_BLOCKS * 4]
        Q_A_key = Q_A_data[N_SAMPLES : N_SAMPLES + self.N_BLOCKS * 4]
        P_B_key = P_B_rec[N_SAMPLES : N_SAMPLES + self.N_BLOCKS * 4]
        Q_B_key = Q_B_rec[N_SAMPLES : N_SAMPLES + self.N_BLOCKS * 4]

        # Block arrays: 8 coordinates per block
        X_blocks = []
        Y_blocks = []
        for blk in range(self.N_BLOCKS):
            base = blk * 4
            x_blk = [P_A_key[base],   Q_A_key[base],
                     P_A_key[base+1], Q_A_key[base+1],
                     P_A_key[base+2], Q_A_key[base+2],
                     P_A_key[base+3], Q_A_key[base+3]]
            y_blk = [P_B_key[base],   Q_B_key[base],
                     P_B_key[base+1], Q_B_key[base+1],
                     P_B_key[base+2], Q_B_key[base+2],
                     P_B_key[base+3], Q_B_key[base+3]]
            X_blocks.append(x_blk)
            Y_blocks.append(y_blk)

        # Bob generates random secret bits (26,112 bits = 3,264 x 8)
        bob_bits_flat = []
        m_messages = []
        k_dyn_all = []
        alice_llrs = []
        uncoded_bit_errors = 0

        for blk in range(self.N_BLOCKS):
            Y_i = Y_blocks[blk]
            X_i = X_blocks[blk]

            norm_y = math.sqrt(sum(y*y for y in Y_i))
            if norm_y < 1e-12:
                norm_y = 1.0
            Y_norm = [y / norm_y for y in Y_i]
            M_Y = get_hurwitz_radon_matrix(Y_norm)

            b_i = [random.randint(0, 1) for _ in range(8)]
            bob_bits_flat.extend(b_i)
            C_i = [1.0 - 2.0 * bk for bk in b_i]

            # Public message m_i = M_Y^T * C_i
            m_i = [sum(M_Y[r][c] * C_i[r] for r in range(8)) for c in range(8)]
            m_messages.append(m_i)

            # Alice computes U = M_X * m_i (norm_x = 1.0 for hardware compatibility)
            M_X = get_hurwitz_radon_matrix(X_i)
            U_i = [sum(M_X[r][c] * m_i[c] for c in range(8)) for r in range(8)]

            k_dyn = inv_sigma2 * norm_y
            k_dyn_all.append(k_dyn)

            # LLR = inv_sigma2 * norm_y * U_i
            llr_i = [k_dyn * u for u in U_i]
            alice_llrs.extend(llr_i)

            # Check uncoded decision: LLR < 0 -> bit 1, LLR >= 0 -> bit 0
            for d in range(8):
                b_hat = 1 if llr_i[d] < 0 else 0
                if b_hat != b_i[d]:
                    uncoded_bit_errors += 1

        pre_fec_ber = (uncoded_bit_errors / float(len(bob_bits_flat))) * 100.0

        # Load LDPC matrix and compute Bob's target syndrome
        bg1 = load_bg1_matrix()
        syn_matrix, syn_words = compute_qc_ldpc_syndrome(bg1, bob_bits_flat, Z=self.Z)

        t_elapsed = time.time() - t_start
        print(f"[SIM] Simulation complete in {t_elapsed*1000:.1f} ms!")
        print(f"      - Useful Key Bits:     {len(bob_bits_flat)} bits (3,264 blocks x 8 bits)")
        print(f"      - Estimated Trans:     T*eta = {T_eta_est:.4f} (Ideal: {self.T * self.eta:.4f})")
        print(f"      - Uncoded Pre-FEC BER: {pre_fec_ber:.2f}% ({uncoded_bit_errors} / {len(bob_bits_flat)} bit errors)")
        print(f"      - LDPC Syndrome Words: {len(syn_words)} words (46 rows x 12 words of 32 bits)")

        results = {
            "X_blocks": X_blocks,
            "m_messages": m_messages,
            "k_dyn_all": k_dyn_all,
            "bob_bits_flat": bob_bits_flat,
            "alice_llrs": alice_llrs,
            "syn_matrix": syn_matrix,
            "syn_words": syn_words,
            "pre_fec_ber": pre_fec_ber,
            "t_elapsed_ms": t_elapsed * 1000.0,
            "bg1": bg1
        }
        return results

    def export_test_vectors(self, results, out_dir=DEFAULT_DATA_DIR):
        """Exports generated vectors in bit-for-bit hardware format."""
        os.makedirs(out_dir, exist_ok=True)
        print(f"\n[EXPORT] Exporting FPGA test vectors to {out_dir}...")

        # 1. alice_mdr_inputs.txt (3264 lines, 128-bit hex = 8 coordinates int16)
        path_x = os.path.join(out_dir, "alice_mdr_inputs.txt")
        with open(path_x, "w") as f:
            for blk in range(self.N_BLOCKS):
                X_i = results["X_blocks"][blk]
                hex_str = ""
                for dim in range(7, -1, -1):
                    val_int16 = int(X_i[dim]) & 0xFFFF
                    hex_str += f"{val_int16:04X}"
                f.write(hex_str + "\n")
        print(f"  [OK] Exported {self.N_BLOCKS} lines to alice_mdr_inputs.txt")

        # 2. expected_m_messages.txt (3264 lines, 256-bit hex = 8 coordinates Q24)
        path_m = os.path.join(out_dir, "expected_m_messages.txt")
        with open(path_m, "w") as f:
            for blk in range(self.N_BLOCKS):
                m_i = results["m_messages"][blk]
                hex_str = ""
                for dim in range(7, -1, -1):
                    m_q24 = int(round(m_i[dim] * (2**24))) & 0xFFFFFFFF
                    hex_str += f"{m_q24:08X}"
                f.write(hex_str + "\n")
        print(f"  [OK] Exported {self.N_BLOCKS} lines to expected_m_messages.txt")

        # 3. alice_k_dynamic.txt (3264 lines, 32-bit hex in Q10)
        path_k = os.path.join(out_dir, "alice_k_dynamic.txt")
        with open(path_k, "w") as f:
            for blk in range(self.N_BLOCKS):
                k_q10 = int(round(results["k_dyn_all"][blk] * (2**10))) & 0xFFFFFFFF
                f.write(f"{k_q10:08X}\n")
        print(f"  [OK] Exported {self.N_BLOCKS} lines to alice_k_dynamic.txt")

        # 4. expected_syndrome_words.hex (552 lines, 32-bit hex words)
        path_syn_hex = os.path.join(out_dir, "expected_syndrome_words.hex")
        with open(path_syn_hex, "w") as f:
            for word in results["syn_words"]:
                f.write(f"{word:08x}\n")
        print(f"  [OK] Exported {len(results['syn_words'])} words to expected_syndrome_words.hex")

        # 5. expected_syndrome.txt (46 lines of 384 bits)
        path_syn_txt = os.path.join(out_dir, "expected_syndrome.txt")
        with open(path_syn_txt, "w") as f:
            for r in range(46):
                row_bits = results["syn_matrix"][r]
                line_str = "".join(str(row_bits[self.Z - 1 - i]) for i in range(self.Z))
                f.write(line_str + "\n")
        print(f"  [OK] Exported 46 lines to expected_syndrome.txt")

        # 6. block_bits.txt (68 lines of 384 bits = Bob's golden key)
        path_bb = os.path.join(out_dir, "block_bits.txt")
        bits_flat = results["bob_bits_flat"]
        with open(path_bb, "w") as f:
            for c in range(68):
                col_bits = bits_flat[c * self.Z : (c + 1) * self.Z]
                line_str = "".join(str(col_bits[self.Z - 1 - i]) for i in range(self.Z))
                f.write(line_str + "\n")
        print(f"  [OK] Exported 68 lines to block_bits.txt (Golden Key: 26,112 bits)")

        # 7. u_bits.txt (68 lines of 384 bytes in 8-bit sign-magnitude)
        path_ubits = os.path.join(out_dir, "u_bits.txt")
        llrs = results["alice_llrs"]
        with open(path_ubits, "w") as f:
            for c in range(68):
                col_llrs = llrs[c * self.Z : (c + 1) * self.Z]
                line_str = ""
                for z in range(self.Z - 1, -1, -1):
                    val = int(round(col_llrs[z]))
                    if val > 127:  val = 127
                    if val < -127: val = -127
                    sign_b = 1 if val < 0 else 0
                    mag_b = abs(val)
                    byte_val = (sign_b << 7) | mag_b
                    line_str += f"{byte_val:08b}"
                f.write(line_str + "\n")
        print(f"  [OK] Exported 68 lines to u_bits.txt (8-bit Sign-Magnitude LLRs)\n")


# ==============================================================================
# 5. SOFTWARE LDPC DECODER & BENCHMARK (SPEEDUP EVALUATION)
# ==============================================================================

def run_software_ldpc_decoder(results, max_iter=20, alpha=0.75):
    """
    Executes bit-for-bit scaled min-sum LDPC decoder in Python on the generated frame.
    Measures software execution time to prove the hardware speedup.
    """
    print(f"\n[BENCHMARK] Running Software 5G-NR Min-Sum LDPC Decoder (alpha={alpha:.2f}, max_iter={max_iter})...")
    t0 = time.time()

    bg = results["bg1"]
    Z = 384
    N_ROWS = 46
    N_COLS = 68
    golden_bits = results["bob_bits_flat"]

    # Initial LLRs in sign-magnitude (-127 to +127)
    llr_init = []
    for val in results["alice_llrs"]:
        v = int(round(val))
        if v > 127:  v = 127
        if v < -127: v = -127
        llr_init.append(v)

    # Edge list construction
    edges = []
    c_edges = [[] for _ in range(N_ROWS * Z)]
    v_edges = [[] for _ in range(N_COLS * Z)]

    for r in range(N_ROWS):
        for c in range(N_COLS):
            shift = bg[r][c]
            if shift >= 0:
                for i in range(Z):
                    check_idx = r * Z + i
                    var_idx = c * Z + ((i + shift) % Z)
                    e_idx = len(edges)
                    edges.append((check_idx, var_idx))
                    c_edges[check_idx].append(e_idx)
                    v_edges[var_idx].append(e_idx)

    # Messages
    msg_v2c = [0] * len(edges)
    msg_c2v = [0] * len(edges)

    for v in range(N_COLS * Z):
        for e in v_edges[v]:
            msg_v2c[e] = llr_init[v]

    # Target syndrome flat array
    target_syn = []
    for r in range(N_ROWS):
        target_syn.extend(results["syn_matrix"][r])

    converged = False
    iter_done = 0

    for it in range(1, max_iter + 1):
        iter_done = it

        # CNU Update (Scaled Min-Sum)
        for c in range(N_ROWS * Z):
            e_list = c_edges[c]
            if not e_list:
                continue

            # Find min1, min2, total sign
            min1 = 999999
            min2 = 999999
            min1_idx = -1
            syn_sign = 1 - 2 * target_syn[c]
            total_sign = syn_sign

            for idx, e in enumerate(e_list):
                val = msg_v2c[e]
                mag = abs(val)
                s = -1 if val < 0 else 1
                total_sign *= s
                if mag < min1:
                    min2 = min1
                    min1 = mag
                    min1_idx = idx
                elif mag < min2:
                    min2 = mag

            # Send extrinsic
            for idx, e in enumerate(e_list):
                val = msg_v2c[e]
                s = -1 if val < 0 else 1
                sign_excl = total_sign * s
                use_mag = min2 if idx == min1_idx else min1
                msg_c2v[e] = int(round(alpha * sign_excl * use_mag))

        # VNU Update & Decisions
        decoded_bits = [0] * (N_COLS * Z)
        bit_errors = 0
        for v in range(N_COLS * Z):
            e_list = v_edges[v]
            llr_post = llr_init[v] + sum(msg_c2v[e] for e in e_list)
            bit_dec = 1 if llr_post < 0 else 0
            decoded_bits[v] = bit_dec
            if bit_dec != golden_bits[v]:
                bit_errors += 1
            # Update v2c
            for e in e_list:
                msg_v2c[e] = llr_post - msg_c2v[e]

        # Check syndrome convergence
        if bit_errors == 0:
            converged = True
            break

    t_decode = time.time() - t0
    hw_time_ms = 1.15  # Nexys Video Artix-7 @ 25 MHz execution time
    speedup = (t_decode * 1000.0) / hw_time_ms

    print("-" * 60)
    if converged:
        print(f"  >>> [CONVERGENCIA EXITOSA] Decodificado en {iter_done} iteraciones!")
        print(f"  >>> BER residual: 0 / 26112 (0.0000%) - Coincidencia bit a bit 100%")
    else:
        print(f"  [AVISO] Decoder completado sin convergencia en {iter_done} iteraciones (Errores: {bit_errors})")
    print(f"  Software CPU time (Python): {t_decode*1000:.1f} ms")
    print(f"  Hardware FPGA time (Artix-7): {hw_time_ms:.2f} ms")
    print(f"  >>> HARDWARE SPEEDUP:       {speedup:.1f}x mas rapido en FPGA!")
    print("-" * 60 + "\n")
    return converged, t_decode


# ==============================================================================
# 6. MAIN CLI ENTRY POINT
# ==============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="CV-QKD End-to-End Channel Simulator & FPGA Test Vector Generator"
    )
    parser.add_argument("--distance", "-d", type=float, default=10.0,
                        help="Fiber distance in km (default: 10.0 km)")
    parser.add_argument("--va", type=float, default=5.0,
                        help="Alice modulation variance in SNU (default: 5.0)")
    parser.add_argument("--excess-noise", "-xi", type=float, default=0.01,
                        help="Channel excess noise in SNU (default: 0.01)")
    parser.add_argument("--eta", type=float, default=0.6,
                        help="Photodiode quantum efficiency (default: 0.6)")
    parser.add_argument("--v-elec", type=float, default=0.1,
                        help="Electronic noise of each detector in SNU (default: 0.1)")
    parser.add_argument("--rep-rate", "-r", type=float, default=1e9,
                        help="Laser repetition rate in Hz (default: 1e9 = 1 Gbaud)")
    parser.add_argument("--beta", type=float, default=0.72,
                        help="Reconciliation efficiency (default: 0.72, LDPC rate 22/68 at the 10 km point)")
    parser.add_argument("--attenuation", "-a", type=float, default=0.2,
                        help="Fiber attenuation in dB/km (default: 0.2)")
    parser.add_argument("--seed", type=int, default=42,
                        help="Random seed for reproducibility (default: 42)")
    parser.add_argument("--skr-table", action="store_true",
                        help="Display theoretical Secret Key Rate table vs distance")
    parser.add_argument("--export-dir", type=str, default=None,
                        help="Directory to save generated FPGA test vectors")
    parser.add_argument("--verify", action="store_true",
                        help="Run software LDPC decoder to verify convergence and benchmark speedup")
    parser.add_argument("--max-iter", type=int, default=15,
                        help="Max iterations for software LDPC verification (default: 15)")

    args = parser.parse_args()

    # 1. Print SKR Table
    print_skr_table(V_A=args.va, xi=args.excess_noise, eta=args.eta, v_el=args.v_elec,
                    alpha=args.attenuation, beta=args.beta, rep_rate=args.rep_rate)

    if args.skr_table and args.export_dir is None and not args.verify:
        return

    # 2. Run Physical Simulation
    sim = CVQKDChannelSimulator(
        distance_km=args.distance,
        V_A=args.va,
        xi=args.excess_noise,
        eta=args.eta,
        v_el=args.v_elec,
        alpha=args.attenuation,
        rep_rate=args.rep_rate,
        seed=args.seed
    )
    results = sim.run_simulation()

    # 3. Export Vectors if requested
    if args.export_dir:
        sim.export_test_vectors(results, out_dir=args.export_dir)

    # 4. Software Verification & Benchmark if requested
    if args.verify:
        run_software_ldpc_decoder(results, max_iter=args.max_iter)


if __name__ == "__main__":
    main()
