/******************************************************************************
 *  TFG: Acelerador Hardware CV-QKD - Subsistema Alice (Nexys Video, MicroBlaze)
 *
 *  Fase 1: reconciliación de la trama de MATLAB (MDR 8D + LDPC) y volcado de la
 *          clave por UART para compararla con la de Bob (tools/run_board.py alice).
 *  Fase 2: la misma trama 1000 veces (las BRAM solo guardan la trama de MATLAB):
 *          todas deben dar la clave de la fase 1. Mide la latencia con el contador
 *          de ciclos del acelerador (registro 0x18). La tasa de éxito frente a la
 *          SNR se obtiene en simulación con tramas nuevas (tools/waterfall_ldpc.sh).
 ******************************************************************************/

#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"

#define ALICE_BASE         0x00004000
#define REG_CTRL           (ALICE_BASE + 0x00)
#define REG_STATUS         (ALICE_BASE + 0x04)
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

#define STREAM_FRAMES      1000

static u32 key_ref[N_KEY_WORDS];                 // Clave de la fase 1

// Lanza una trama (MDR + LDPC con K dinámico) y espera a que el acelerador termine.
// Devuelve el registro de estado final, o 0 si se agota el tiempo.
static u32 run_frame(void)
{
    Xil_Out32(REG_CTRL, CTRL_SOFT_RESET);
    Xil_Out32(REG_CTRL, 0);
    Xil_Out32(REG_K_MODE, 1);                    // K dinámico (ram_k)
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
    u32 status = run_frame();
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
        key_ref[w] = Xil_In32(KEY_BRAM_BASE + (w * 4));
        xil_printf("%08X\r\n", key_ref[w]);
    }
    xil_printf("--- KEY_END ---\r\n");

    // =========================================================================
    // FASE 2: ROBUSTEZ Y LATENCIA (1000 TRAMAS)
    // =========================================================================
    xil_printf("\r\n[ALICE] Fase 2: %d reconciliaciones de la misma trama...\r\n", STREAM_FRAMES);

    u32 ok = 0, wrong_key = 0, failed = 0, timeouts = 0;
    u32 cyc_min = 0xFFFFFFFF, cyc_max = 0;
    u64 cyc_sum = 0;

    for (int f = 0; f < STREAM_FRAMES; f++) {
        status = run_frame();
        if (status == 0) { timeouts++; continue; }
        if (!(status & ST_KEY_READY)) { failed++; continue; }

        int same = 1;
        for (int w = 0; w < N_KEY_WORDS; w++)
            if (Xil_In32(KEY_BRAM_BASE + (w * 4)) != key_ref[w]) same = 0;
        if (!same) { wrong_key++; continue; }

        ok++;
        cycles = Xil_In32(REG_CYCLES);
        cyc_sum += cycles;
        if (cycles < cyc_min) cyc_min = cycles;
        if (cycles > cyc_max) cyc_max = cycles;
    }

    u32 cyc_avg  = ok ? (u32)(cyc_sum / ok) : 0;
    u32 lat_us   = cyc_avg / CLK_MHZ;
    u32 thr_kbps = lat_us ? (FRAME_BITS * 1000u / lat_us) : 0;

    xil_printf("================================================================\r\n");
    xil_printf(" Tramas con la clave de la fase 1 : %d / %d\r\n", ok, STREAM_FRAMES);
    xil_printf(" Clave distinta / sin converger   : %d / %d\r\n", wrong_key, failed);
    xil_printf(" Timeouts                         : %d\r\n", timeouts);
    xil_printf(" Ciclos por trama (min/media/max) : %d / %d / %d\r\n", ok ? cyc_min : 0, cyc_avg, cyc_max);
    xil_printf(" Latencia media                   : %d.%02d ms a %d MHz\r\n",
               lat_us / 1000, (lat_us % 1000) / 10, CLK_MHZ);
    xil_printf(" Throughput de reconciliacion     : %d.%02d Mbps\r\n", thr_kbps / 1000, (thr_kbps % 1000) / 10);
    xil_printf("================================================================\r\n");
    xil_printf("[STREAM_DONE]\r\n");

    return 0;
}
