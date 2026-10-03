/******************************************************************************
 *  TFG: Acelerador Hardware CV-QKD - Subsistema Alice (Nexys Video, MicroBlaze)
 *
 *  Fase 1: reconciliación de la trama de MATLAB (MDR 8D + LDPC) y volcado de la
 *          clave por UART para compararla con la de Bob (tools/run_board.py alice).
 *  Fase 2: barrido del factor K (SNR) en 10 escalones de 100 tramas: tasa de
 *          éxito, iteraciones del LDPC y latencia medida por el contador de ciclos
 *          del acelerador (registro 0x18).
 ******************************************************************************/

#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"

#define ALICE_BASE         0x00004000
#define REG_CTRL           (ALICE_BASE + 0x00)
#define REG_STATUS         (ALICE_BASE + 0x04)
#define REG_K_FACTOR       (ALICE_BASE + 0x08)
#define REG_K_MODE         (ALICE_BASE + 0x0C)
#define REG_CYCLES         (ALICE_BASE + 0x18) // Ciclos de reloj de la última ejecución
#define KEY_BRAM_BASE      (ALICE_BASE + 0x0A00) // 816 palabras

// Bits de REG_CTRL y REG_STATUS
#define CTRL_SOFT_RESET    0x01
#define CTRL_START_AUTO    0x0A                  // start_mdr + auto_run (MDR y después LDPC)
#define ST_LDPC_DONE       (1u << 1)
#define ST_LDPC_SUCCESS    (1u << 2)
#define ST_KEY_READY       (1u << 3)
#define ST_BUSY            (1u << 4)
#define ST_ITERS(s)        (((s) >> 8) & 0xFF)

#define CLK_MHZ            25                    // Reloj del acelerador (clk_wiz de la BD)
#define N_KEY_WORDS        816                   // 26.112 bits
#define FRAME_BITS         26112

#define NUM_K_STEPS        10
#define FRAMES_PER_STEP    100
#define TOTAL_STREAM_FRAMES (NUM_K_STEPS * FRAMES_PER_STEP)

typedef struct {
    u32 k_mode;
    u32 k_factor;
    const char *name;
    const char *fiber_desc;
} k_config_t;

static const k_config_t K_CONFIGS[NUM_K_STEPS] = {
    { 1, 38, "Dinamico (ram_k)", "Canal Nominal  " },
    { 0, 16, "Escalar  K = 16  ", "SNR Estable     " },
    { 0, 15, "Escalar  K = 15  ", "Fibra ~30 km    " },
    { 0, 14, "Escalar  K = 14  ", "Fibra ~35 km    " },
    { 0, 13, "Escalar  K = 13  ", "Fibra ~40 km    " },
    { 0, 12, "Escalar  K = 12  ", "Fibra ~45 km    " },
    { 0, 11, "Escalar  K = 11  ", "Alta Exigencia  " },
    { 0, 10, "Escalar  K = 10  ", "Cerca del Umbral" },
    { 0,  9, "Escalar  K =  9  ", "Regimen Limite  " },
    { 0,  8, "Escalar  K =  8  ", "Borde Waterfall " }
};

typedef struct {
    u32 success;
    u32 fail;
    u32 timeout;
    u32 avg_iters;
    u32 lat_us;
    u32 thr_kbps;
} step_stats_t;

static step_stats_t step_results[NUM_K_STEPS];

// Lanza una trama (MDR + LDPC) y espera a que el acelerador termine.
// Devuelve el registro de estado final, o 0 si se agota el tiempo.
static u32 run_frame(u32 k_mode, u32 k_factor)
{
    Xil_Out32(REG_CTRL, CTRL_SOFT_RESET);
    Xil_Out32(REG_CTRL, 0);
    Xil_Out32(REG_K_MODE, k_mode);
    if (k_mode == 0) Xil_Out32(REG_K_FACTOR, k_factor);
    Xil_Out32(REG_CTRL, CTRL_START_AUTO);

    for (u32 polls = 0; polls < 1000000; polls++) {
        u32 status = Xil_In32(REG_STATUS);
        if ((status & ST_LDPC_DONE) && !(status & ST_BUSY)) return status;
    }
    return 0;
}

int main()
{
    xil_printf("\r\n========================================\r\n");
    xil_printf("   CV-QKD ALICE HARDWARE ACCELERATOR    \r\n");
    xil_printf("   Nexys Video (Artix-7 XC7A200T)       \r\n");
    xil_printf("========================================\r\n");

    // =========================================================================
    // FASE 1: VERIFICACION DE LA CLAVE DORADA (TRAMA 1)
    // =========================================================================
    xil_printf("[ALICE] Lanzando reconciliacion hardware (MDR + LDPC)...\r\n");
    u32 status = run_frame(1, 0);   // K dinámico (ram_k)
    if (!(status & ST_KEY_READY)) {
        xil_printf("[ERROR] La trama 1 no se reconcilio. Status = 0x%08X\r\n", status);
        return -1;
    }
    u32 cycles = Xil_In32(REG_CYCLES);
    xil_printf("[ALICE] Reconciliacion completada: %d iteraciones LDPC, %d ciclos (%d us a %d MHz)\r\n",
               ST_ITERS(status), cycles, cycles / CLK_MHZ, CLK_MHZ);

    // Volcar las 816 palabras de la clave b_hat (26.112 bits) por UART
    xil_printf("\r\n--- KEY_START ---\r\n");
    for (int w = 0; w < N_KEY_WORDS; w++) {
        xil_printf("%08X\r\n", Xil_In32(KEY_BRAM_BASE + (w * 4)));
    }
    xil_printf("--- KEY_END ---\r\n");

    // =========================================================================
    // FASE 2: BARRIDO DE SNR / RUIDO DE CANAL (FACTOR K) EN SILICIO
    // =========================================================================
    xil_printf("\r\n========================================================================\r\n");
    xil_printf("   INICIANDO BARRIDO DE SNR Y FACTOR K EN SILICIO (%d TRAMAS)          \r\n", TOTAL_STREAM_FRAMES);
    xil_printf("   - 10 escalones de SNR x 100 tramas/escalon                          \r\n");
    xil_printf("   - Latencia medida con el contador de ciclos del acelerador          \r\n");
    xil_printf("========================================================================\r\n\r\n");

    u32 global_success = 0, global_timeout = 0, global_frame_idx = 0;

    for (int s = 0; s < NUM_K_STEPS; s++) {
        u32 step_success = 0, step_fail = 0, step_timeout = 0;
        u64 step_iters = 0, step_cycles = 0;

        xil_printf("[ESCALON %2d/10] Probando 100 tramas con %s (%s)...\r\n",
                   s + 1, K_CONFIGS[s].name, K_CONFIGS[s].fiber_desc);

        for (int f = 1; f <= FRAMES_PER_STEP; f++) {
            global_frame_idx++;
            status = run_frame(K_CONFIGS[s].k_mode, K_CONFIGS[s].k_factor);
            cycles = Xil_In32(REG_CYCLES);

            if (status == 0) {
                step_timeout++;
            } else if (status & ST_KEY_READY) {
                step_success++;
                step_iters  += ST_ITERS(status);
                step_cycles += cycles;
            } else {
                step_fail++;
            }

            // Diagnóstico de la primera trama del escalón
            if (f == 1) {
                xil_printf("  -> [DIAG Trama %4d] Status = 0x%08X (KeyReady=%d, Succ=%d, Iters=%2d) | Word0 = 0x%08X | Ciclos = %d\r\n",
                           global_frame_idx, status, (status >> 3) & 1, (status >> 2) & 1,
                           ST_ITERS(status), Xil_In32(KEY_BRAM_BASE), cycles);
            }
        }
        global_success += step_success;
        global_timeout += step_timeout;

        // Métricas del escalón (sobre las tramas reconciliadas)
        step_stats_t *r = &step_results[s];
        r->success   = step_success;
        r->fail      = step_fail;
        r->timeout   = step_timeout;
        r->avg_iters = step_success ? (u32)(step_iters / step_success) : 0;
        r->lat_us    = step_success ? (u32)(step_cycles / step_success / CLK_MHZ) : 0;
        r->thr_kbps  = r->lat_us ? (FRAME_BITS * 1000u / r->lat_us) : 0;

        xil_printf("  [RESULTADO] %s | Exito: %3d%% | Iters Medias: %2d | Latencia: %d.%02d ms | Throughput: %d.%02d Mbps\r\n\r\n",
                   K_CONFIGS[s].name, (step_success * 100) / FRAMES_PER_STEP, r->avg_iters,
                   r->lat_us / 1000, (r->lat_us % 1000) / 10,
                   r->thr_kbps / 1000, (r->thr_kbps % 1000) / 10);
    }

    xil_printf("====================================================================================================\r\n");
    xil_printf("       TABLA FINAL: IMPACTO DE LA SNR / FACTOR K EN LA CONVERGENCIA LDPC EN SILICIO                 \r\n");
    xil_printf("====================================================================================================\r\n");
    xil_printf(" Paso | Configuracion        | Condicion        | Exito    | Iters Medias | Latencia  | Throughput  \r\n");
    xil_printf("----------------------------------------------------------------------------------------------------\r\n");
    for (int s = 0; s < NUM_K_STEPS; s++) {
        step_stats_t *r = &step_results[s];
        xil_printf("  %2d  | %s | %s |  %3d%%   |      %2d      |  %d.%02d ms  | %d.%02d Mbps\r\n",
                   s + 1, K_CONFIGS[s].name, K_CONFIGS[s].fiber_desc,
                   (r->success * 100) / FRAMES_PER_STEP, r->avg_iters,
                   r->lat_us / 1000, (r->lat_us % 1000) / 10,
                   r->thr_kbps / 1000, (r->thr_kbps % 1000) / 10);
    }
    xil_printf("====================================================================================================\r\n");
    xil_printf(" Total tramas analizadas : %d\r\n", TOTAL_STREAM_FRAMES);
    xil_printf(" Tramas corregidas       : %d / %d (%d.%02d%%)\r\n",
               global_success, TOTAL_STREAM_FRAMES,
               (global_success * 100) / TOTAL_STREAM_FRAMES,
               ((global_success * 10000) / TOTAL_STREAM_FRAMES) % 100);
    xil_printf(" Timeouts                : %d\r\n", global_timeout);
    xil_printf(" Total bits procesados   : %d bits\r\n", TOTAL_STREAM_FRAMES * FRAME_BITS);
    xil_printf("====================================================================================================\r\n");
    xil_printf("[STREAM_DONE]\r\n");

    return 0;
}
