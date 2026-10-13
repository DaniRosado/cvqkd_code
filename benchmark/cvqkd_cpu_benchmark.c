/******************************************************************************
 *  TFG: Acelerador Hardware CV-QKD - Benchmark de Rendimiento en CPU
 *  Archivo: cvqkd_cpu_benchmark.c
 *
 *  Descripción:
 *  La reconciliación de Alice en C, con el mismo trabajo que el acelerador de la FPGA
 *  (Artix-7 XC7A200T a 25 MHz) y sobre la misma trama (export_benchmark_data.py):
 *    1. MDR 8D: LLR a partir de X, los mensajes m de Bob y el factor K (mdr_alice_datapath).
 *    2. LDPC 5G-NR BG1 (Z=384, N=26.112) Min-Sum por capas con alpha = 0,75, con la
 *       aritmética y el criterio de parada de la RTL (vnu_node, cnu_serial_node,
 *       ldpc_layer_datapath, syndrome_checker): debe dar las mismas iteraciones.
 *    3. Extracción de la clave.
 *  La clave se compara con la de Bob fuera del tiempo medido.
 *
 *  Compatibilidad:
 *    - Host PC (Linux x86-64 / GCC -O3): Usa clock_gettime(CLOCK_MONOTONIC)
 *    - PYNQ-Z2 Baremetal (ARM Cortex-A9 @ 650 MHz en Vitis): Usa xtime_l.h
 *    - PYNQ-Z2 Linux (Ubuntu ARMv7 / GCC -O3): Usa clock_gettime
 *    - MicroBlaze Baremetal (Artix-7 @ 25 MHz en Vitis)
 ******************************************************************************/

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#if defined(PLATFORM_ARM_BAREMETAL) || (defined(__arm__) && !defined(__linux__))
    /* Vitis Baremetal en Zynq-7000 (ARM Cortex-A9) */
    #include "xparameters.h"
    #include "xil_printf.h"
    #include "xil_io.h"
    #define IS_XILINX_BAREMETAL 1
    #define PRINTF xil_printf

    #define GLOBAL_TMR_BASEADDR         0xF8F00200U
    #define GTIMER_COUNTER_LOWER_OFFSET 0x00U
    #define GTIMER_COUNTER_UPPER_OFFSET 0x04U
    #define GTIMER_CONTROL_OFFSET       0x08U
    #define GTIMER_FREQ_HZ              325000000.0

    static inline void init_global_timer(void) {
        Xil_Out32(GLOBAL_TMR_BASEADDR + GTIMER_CONTROL_OFFSET, 0x0);
        Xil_Out32(GLOBAL_TMR_BASEADDR + GTIMER_COUNTER_LOWER_OFFSET, 0x0);
        Xil_Out32(GLOBAL_TMR_BASEADDR + GTIMER_COUNTER_UPPER_OFFSET, 0x0);
        Xil_Out32(GLOBAL_TMR_BASEADDR + GTIMER_CONTROL_OFFSET, 0x1);
    }

    static inline uint64_t read_global_timer(void) {
        uint32_t high, low;
        do {
            high = Xil_In32(GLOBAL_TMR_BASEADDR + GTIMER_COUNTER_UPPER_OFFSET);
            low = Xil_In32(GLOBAL_TMR_BASEADDR + GTIMER_COUNTER_LOWER_OFFSET);
        } while (Xil_In32(GLOBAL_TMR_BASEADDR + GTIMER_COUNTER_UPPER_OFFSET) != high);
        return (((uint64_t)high) << 32) | low;
    }
#elif defined(PLATFORM_MB_BAREMETAL) || defined(__MICROBLAZE__)
    /* Vitis Baremetal en MicroBlaze */
    #include "xparameters.h"
    #include "xil_printf.h"
    #include "xil_io.h"
    #define IS_XILINX_BAREMETAL 1
    #define PRINTF xil_printf
#else
    /* Linux POSIX (Host x86-64 o Linux PYNQ) */
    #include <time.h>
    #define IS_POSIX 1
    #define PRINTF printf
#endif

#include "cvqkd_benchmark_data.h"

#define MAX_ITERS 200   /* Como la RTL (ldpc_controller_fsm) */
#define Q_MAX     127   /* Mensajes y LLR hacia la CNU: 8 bits en signo-magnitud */
#define L_MAX     511   /* LLR a posteriori: 10 bits en signo-magnitud */

static int8_t   llr_in[N_CODE_BITS];                       /* Salida del MDR */
static int16_t  llr_post[N_CODE_BITS];                     /* LLR a posteriori (L_BRAM); bit duro = signo */
static int8_t   r_msg[BG_ROWS][MAX_ROW_DEG][Z_LIFTING];    /* Mensajes de las CNU (R_BRAM) */
static uint8_t  target_syn[BG_ROWS][Z_LIFTING];            /* Síndrome de Bob */
static uint32_t key_out[N_KEY_WORDS];                      /* Clave reconciliada */

/* Función para obtener tiempo en microsegundos */
static double get_time_us(void) {
#if defined(PLATFORM_ARM_BAREMETAL) || (defined(__arm__) && !defined(__linux__))
    uint64_t t = read_global_timer();
    return (double)t * 1000000.0 / GTIMER_FREQ_HZ;
#elif defined(IS_POSIX)
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000000.0 + (double)ts.tv_nsec / 1000.0;
#else
    return 0.0;
#endif
}

/* Helper para imprimir números con decimales compatible con xil_printf y printf */
static void print_metric(const char *prefix, double val, const char *suffix, int decimals) {
#if defined(IS_XILINX_BAREMETAL)
    int mult = 1;
    for (int k = 0; k < decimals; k++) mult *= 10;
    int sign = (val < 0.0) ? -1 : 1;
    double abs_val = val * (double)sign;
    int int_part = (int)abs_val;
    int frac_part = (int)((abs_val - (double)int_part) * (double)mult + 0.5);
    if (frac_part >= mult) {
        int_part += 1;
        frac_part -= mult;
    }
    if (decimals == 1) {
        PRINTF("%s%s%d.%01d%s", prefix, (sign < 0) ? "-" : "", int_part, frac_part, suffix);
    } else if (decimals == 2) {
        PRINTF("%s%s%d.%02d%s", prefix, (sign < 0) ? "-" : "", int_part, frac_part, suffix);
    } else {
        PRINTF("%s%s%d.%03d%s", prefix, (sign < 0) ? "-" : "", int_part, frac_part, suffix);
    }
#else
    if (decimals == 1) {
        printf("%s%.1f%s", prefix, val, suffix);
    } else if (decimals == 2) {
        printf("%s%.2f%s", prefix, val, suffix);
    } else {
        printf("%s%.3f%s", prefix, val, suffix);
    }
#endif
}

/* Rotación 8D del MDR (tablas de mdr_alice_datapath.sv) */
static const uint8_t M_IDX[8][8] = {
    {0, 1, 2, 3, 4, 5, 6, 7}, {1, 0, 3, 2, 5, 4, 7, 6}, {2, 3, 0, 1, 6, 7, 4, 5}, {3, 2, 1, 0, 7, 6, 5, 4},
    {4, 5, 6, 7, 0, 1, 2, 3}, {5, 4, 7, 6, 1, 0, 3, 2}, {6, 7, 4, 5, 2, 3, 0, 1}, {7, 6, 5, 4, 3, 2, 1, 0}
};
static const uint8_t M_NEG[8][8] = {
    {0, 0, 0, 0, 0, 0, 0, 0}, {1, 0, 1, 0, 1, 0, 0, 1}, {1, 0, 0, 1, 1, 1, 0, 0}, {1, 1, 0, 0, 1, 0, 1, 0},
    {1, 0, 0, 0, 0, 1, 1, 1}, {1, 1, 0, 1, 0, 0, 0, 1}, {1, 1, 1, 0, 0, 1, 0, 0}, {1, 0, 1, 1, 0, 0, 1, 0}
};

static inline int clamp(int v, int max) {
    return (v > max) ? max : (v < -max) ? -max : v;
}

/* 1. MDR 8D: LLR = (U' x K) >> 31, con U' = rotación de X por el mensaje m (Q24 -> Q21) */
static void mdr_alice(void) {
    for (int blk = 0; blk < N_CODE_BITS / 8; blk++) {
        const int16_t *x = &MDR_X[8 * blk];
        int32_t m[8];
        for (int c = 0; c < 8; c++) m[c] = (int32_t)((uint32_t)MDR_M[8 * blk + c] << 5) >> 8;   /* bits 26:3 */

        for (int row = 0; row < 8; row++) {
            int64_t u = 0;
            for (int c = 0; c < 8; c++) {
                int xv = x[M_IDX[row][c]];
                u += (int64_t)(M_NEG[row][c] ? -xv : xv) * m[c];
            }
            llr_in[8 * blk + row] = (int8_t)clamp((int32_t)((u * MDR_K[blk]) >> 31), Q_MAX);
        }
    }
}

/* 2. LDPC Min-Sum por capas. Devuelve las iteraciones, o 0 si no converge en MAX_ITERS. */
static int ldpc_decode(void) {
    /* Carga del síndrome (552 palabras -> 46 filas de 384 bits) y de los LLR del MDR */
    for (int r = 0; r < BG_ROWS; r++)
        for (int i = 0; i < Z_LIFTING; i++)
            target_syn[r][i] = (GOLDEN_SYN_WORDS[r * 12 + i / 32] >> (i % 32)) & 1;
    for (int v = 0; v < N_CODE_BITS; v++) llr_post[v] = llr_in[v];
    memset(r_msg, 0, sizeof(r_msg));   /* En la primera iteración la RTL toma R_old = 0 */

    for (int it = 1; it <= MAX_ITERS; it++) {
        int converged = 1;   /* Todas las filas cumplen su síndrome y ningún bit duro cambia */

        for (int r = 0; r < BG_ROWS; r++) {
            int deg = BG_ROW_DEG[r];
            const bg_edge_t *edges = BG_EDGES[r];

            for (int i = 0; i < Z_LIFTING; i++) {
                int v_idx[MAX_ROW_DEG], lq_full[MAX_ROW_DEG], lq_sign[MAX_ROW_DEG];
                int min1 = Q_MAX, min2 = Q_MAX, min1_idx = 0, total_sign = 0;

                /* Pasada 0 (VNU -> CNU): L_q = L - R_old, saturado a 8 bits; mínimos y signo */
                for (int d = 0; d < deg; d++) {
                    int rot = i + edges[d].shift;
                    int v = edges[d].col * Z_LIFTING + (rot >= Z_LIFTING ? rot - Z_LIFTING : rot);
                    int full = llr_post[v] - r_msg[r][d][i];
                    int mag = abs(clamp(full, Q_MAX));
                    v_idx[d] = v;
                    lq_full[d] = full;
                    lq_sign[d] = full < 0;
                    total_sign ^= lq_sign[d];
                    if (d == 0 || mag < min1) {
                        min2 = (d == 0) ? Q_MAX : min1;
                        min1 = mag;
                        min1_idx = d;
                    } else if (mag < min2) {
                        min2 = mag;
                    }
                }

                /* Pasada 1 (CNU -> VNU): R_new = 0,75 x mínimo; L = L_q + R_new, saturado a 10 bits */
                int parity = 0;
                for (int d = 0; d < deg; d++) {
                    int raw = (d == min1_idx) ? min2 : min1;
                    int mag = raw - (raw >> 2);
                    int r_new = (total_sign ^ lq_sign[d] ^ target_syn[r][i]) ? -mag : mag;
                    int l_new = clamp(lq_full[d] + r_new, L_MAX);
                    int bit = l_new < 0;

                    if (bit != (llr_post[v_idx[d]] < 0)) converged = 0;
                    r_msg[r][d][i] = (int8_t)r_new;
                    llr_post[v_idx[d]] = (int16_t)l_new;
                    parity ^= bit;
                }
                if (parity != target_syn[r][i]) converged = 0;
            }
        }
        if (converged) return it;
    }
    return 0;
}

/* 3. Clave: los 26.112 bits duros (signo del LLR a posteriori), en 816 palabras */
static void extract_key(void) {
    for (int w = 0; w < N_KEY_WORDS; w++) {
        uint32_t word = 0;
        for (int b = 0; b < 32; b++) word |= (uint32_t)(llr_post[32 * w + b] < 0) << b;
        key_out[w] = word;
    }
}

int main(void) {
    PRINTF("\r\n========================================================================\r\n");
    PRINTF("   CV-QKD: RECONCILIACION DE ALICE EN CPU FRENTE AL ACELERADOR FPGA     \r\n");
    PRINTF("   MDR 8D + LDPC 5G-NR BG1 Min-Sum por capas (N=26112, Z=384) + clave   \r\n");
#if defined(PLATFORM_ARM_BAREMETAL) || (defined(__arm__) && !defined(__linux__))
    PRINTF("   CPU: ARM Cortex-A9 (Zynq-7020 a 650 MHz, PYNQ-Z2, sin sistema operativo)\r\n");
    init_global_timer();
#else
    PRINTF("   CPU: PC con Linux (GCC -O3)\r\n");
#endif
    PRINTF("========================================================================\r\n\r\n");

    const int NUM_FRAMES = 50;
    double us_mdr = 0.0, us_ldpc = 0.0, us_key = 0.0;
    int iters = 0, key_ok = 0;

    for (int f = 0; f < NUM_FRAMES; f++) {
        double t0 = get_time_us();
        mdr_alice();
        double t1 = get_time_us();
        iters = ldpc_decode();
        double t2 = get_time_us();
        extract_key();
        double t3 = get_time_us();

        us_mdr  += t1 - t0;
        us_ldpc += t2 - t1;
        us_key  += t3 - t2;
        key_ok  += iters && memcmp(key_out, GOLDEN_KEY_WORDS, sizeof(key_out)) == 0;
    }
    us_mdr  /= NUM_FRAMES;
    us_ldpc /= NUM_FRAMES;
    us_key  /= NUM_FRAMES;
    double us_total = us_mdr + us_ldpc + us_key;

    if (key_ok != NUM_FRAMES || iters == 0) {
        PRINTF("[ERROR] Clave identica a la de Bob en %d / %d tramas (%d iteraciones)\r\n", key_ok, NUM_FRAMES, iters);
        return -1;
    }

    /* FPGA de Alice (Nexys Video, 25 MHz), con su contador de ciclos: 27.561 ciclos fijos
     * (carga del síndrome, MDR y clave) + 1.094 por iteración del LDPC. */
    const double FPGA_ITER_US  = 1094.0 / 25.0;
    const double FPGA_FIXED_US = 27561.0 / 25.0;
    double fpga_total = FPGA_FIXED_US + FPGA_ITER_US * iters;

    PRINTF("  * Tramas con la clave de Bob:   %d / %d\r\n", key_ok, NUM_FRAMES);
    PRINTF("  * Iteraciones del LDPC:         %d (la FPGA: 13 con esta trama)\r\n", iters);
    PRINTF("  ----------------------------------------------------------------------\r\n");
    print_metric("  * CPU, MDR 8D:                  ", us_mdr / 1000.0, " ms\r\n", 3);
    print_metric("  * CPU, LDPC:                    ", us_ldpc / 1000.0, " ms\r\n", 3);
    print_metric("  * CPU, clave:                   ", us_key / 1000.0, " ms\r\n", 3);
    print_metric("  * CPU, trama completa:          ", us_total / 1000.0, " ms\r\n", 3);
    print_metric("  * FPGA, trama completa:         ", fpga_total / 1000.0, " ms\r\n", 3);
    PRINTF("  ----------------------------------------------------------------------\r\n");
    print_metric("  * CPU por iteracion del LDPC:   ", us_ldpc / iters, " us\r\n", 1);
    print_metric("  * FPGA por iteracion del LDPC:  ", FPGA_ITER_US, " us\r\n", 2);
    print_metric("  * Aceleracion por iteracion:    ", (us_ldpc / iters) / FPGA_ITER_US, "x\r\n", 1);
    print_metric("  * Factor de Aceleracion (trama completa): ", us_total / fpga_total, "x\r\n", 1);
    PRINTF("========================================================================\r\n\r\n");

    return 0;
}
