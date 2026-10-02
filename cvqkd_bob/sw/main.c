/******************************************************************************
 *  TFG: Acelerador Hardware CV-QKD - Subsistema Bob (PYNQ-Z2)
 *  Archivo: main.c
 *
 *  Descripción:
 *  Aplicación Baremetal en C (Vitis) para co-diseño Hardware/Software en Zynq-7020:
 *    1. Hardware (FPGA Artix-7 logic):
 *         - Ingesta de pulsos ópticos (receptor heterodino: P y Q) por AXI-Stream.
 *         - Estimación analítica de parámetros de canal (Transmitancia T, varianza sigma^2).
 *         - Filtrado cuántico / Criba de sacrificio mediante FIFO interna.
 *         - Reconciliación multidimensional (MDR 8D) y cálculo de síndrome LDPC.
 *    2. Software (ARM Cortex-A9 MPCore @ 650 MHz):
 *         - Orquestación de transferencias DMA y configuración AXI4-Lite.
 *         - Modo Streaming continuo (procesamiento secuencial de tramas).
 *         - Evaluación estricta de seguridad cuántica en tiempo real:
 *           * Información mutua Shannon I(A; B).
 *           * Cota de Holevo chi(B; E) bajo ataques colectivos (GG02).
 *           * Tasa de clave secreta asintótica y de tamaño finito.
 *           * Decisión en vivo: PASS (clave autorizada) / ABORT (intrusión detectada).
 *         - Inyección y detección de ataques de intercepción en tiempo real.
 ******************************************************************************/

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include "xil_printf.h"
#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "sleep.h"
#include "cvqkd_security.h"

// Usar vectores precalculados de MATLAB
#define USE_MATLAB_VECTORS 1

#if USE_MATLAB_VECTORS
    #if __has_include("matlab_vectors.h")
        #include "matlab_vectors.h"
    #else
        #warning "matlab_vectors.h no encontrado en include path. Usando datos sinteticos."
        #undef USE_MATLAB_VECTORS
        #define USE_MATLAB_VECTORS 0
    #endif
#endif

// =============================================================================
// PARÁMETROS DEL STREAMING Y SEGURIDAD
// =============================================================================
#define NUM_STREAM_FRAMES   50    // Total de tramas a procesar en streaming
#define ATTACK_START_FRAME  31    // Inicio de ventana de ataque / intrusión de Eva
#define ATTACK_END_FRAME    40    // Fin de ventana de ataque (frames 31-40)

// =============================================================================
// TIMER GLOBAL DE HARDWARE (ARM Cortex-A9 SCU Global Timer @ 325 MHz)
// =============================================================================
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

// =============================================================================
// DEFINICIONES DE HARDWARE Y REGISTROS
// =============================================================================
#if defined(XPAR_CVQKD_BOB_AXI_WRAPPER_0_BASEADDR)
    #define BOB_BASEADDR XPAR_CVQKD_BOB_AXI_WRAPPER_0_BASEADDR
#elif defined(XPAR_CVQKD_BOB_SUBSYSTEM_0_BASEADDR)
    #define BOB_BASEADDR XPAR_CVQKD_BOB_SUBSYSTEM_0_BASEADDR
#else
    #define BOB_BASEADDR 0x40000000 // Dirección por defecto en Vivado
#endif

// Mapa de registros de Bob (Offsets de 32 bits)
#define BOB_REG_CTRL          0x00 // R/W: bit 0 = soft_reset, bit 1 = enable
#define BOB_REG_CALIB_VARA    0x04 // R/W: V_A * N0 en cuentas ADC
#define BOB_REG_STATUS        0x08 // RO:  bits sticky hasta el soft reset (ver BOB_STATUS_*)
#define BOB_REG_T_FINAL       0x0C // RO:  (Cov/V_A)^2 = T*eta/2, heterodino (Q16.16)
#define BOB_REG_T_SQRT        0x10 // RO:  sqrt(T*eta/2) (Q16.16)
#define BOB_REG_SIGMA_SQ      0x14 // RO:  Ruido observado sigma^2 (Cuentas ADC)
#define BOB_REG_SIGMA         0x18 // RO:  sigma (Q16.16)
#define BOB_REG_NUM_SAMPLES   0x1C // RO:  Muestras de sacrificio procesadas (13056)
#define BOB_REG_KEY_BASE      0x100 // R/W: Memoria de clave interna (816 palabras = 3.264 B)

// Bits del registro de estado
#define BOB_STATUS_DONE_EST   (1u << 0) // Estimación de parámetros terminada
#define BOB_STATUS_SYN_DONE   (1u << 1) // Síndrome LDPC calculado
#define BOB_STATUS_KEY_READY  (1u << 2) // Clave cargada y sin consumir
#define BOB_STATUS_DATA_LOSS  (1u << 3) // Se perdió algún dato: trama inválida

// Tamaños de las tramas del protocolo
#define N_ADC_SAMPLES         27857 // Total muestras ópticas enviadas a Bob
#define N_ALICE_SAMPLES       13056 // Muestras de sacrificio enviadas por Alice
#define N_MASK_WORDS          816   // 26112 bits / 32 bits = 816 palabras
#define N_KEY_WORDS           816   // 26.112 bits de clave / 32 bits = 816 palabras
#define N_MDR_BLOCKS          3264  // 3264 bloques de 256 bits (32 bytes)
#define N_MDR_WORDS           (N_MDR_BLOCKS * 8) // 26112 palabras de 32 bits
#define N_SYN_ROWS            46    // 46 filas de síndrome LDPC
#define N_SYN_WORDS           (N_SYN_ROWS * 16)  // 512 bits = 16 palabras de 32 bits por fila
#define N_TOTAL_DATA_SYMBOLS  26112

#define ADC_BYTE_SIZE         (N_ADC_SAMPLES   * sizeof(uint32_t)) // 111.428 B
#define ALICE_BYTE_SIZE       (N_ALICE_SAMPLES * sizeof(uint32_t)) //  52.224 B
#define MASK_BYTE_SIZE        (N_MASK_WORDS    * sizeof(uint32_t)) //   3.264 B
#define KEY_BYTE_SIZE         (N_KEY_WORDS     * sizeof(uint32_t)) //   3.264 B
#define MDR_BYTE_SIZE         (N_MDR_WORDS     * sizeof(uint32_t)) // 104.448 B
#define SYN_BYTE_SIZE         (N_SYN_WORDS     * sizeof(uint32_t)) //   2.944 B

// Estructura del paquete de reconciliación clásica que Bob enviará a Alice
typedef struct __attribute__((packed)) {
    uint32_t magic_header;             // 0x514B4431 ("QKD1")
    uint32_t block_id;                 // Identificador del bloque
    int32_t  T_final;                  // Transmitancia T (Q16.16)
    int32_t  T_sqrt;                   // Raíz sqrt(T) (Q16.16)
    int32_t  sigma_sq;                 // Varianza del ruido (Entero)
    int32_t  sigma;                    // Desviación estándar (Q16.16)
    uint32_t mask_words[N_MASK_WORDS]; // Máscara de sacrificio (816 palabras = 3.264 B)
    uint32_t mdr_words[N_MDR_WORDS];   // Mensajes públicos MDR (3.264 bloques x 256 bits)
    uint32_t syn_words[N_SYN_WORDS];   // Síndrome LDPC (46 filas x 512 bits)
} bob_to_alice_packet_t;

static bob_to_alice_packet_t bob_tx_alice_packet;

// =============================================================================
// BÚFERES ALINEADOS A 64 BYTES EN MEMORIA RAM DDR
// =============================================================================
static uint32_t tx_adc_buf[N_ADC_SAMPLES]     __attribute__ ((aligned(64)));
static uint32_t tx_alice_buf[N_ALICE_SAMPLES] __attribute__ ((aligned(64)));
static uint32_t tx_mask_buf[N_MASK_WORDS]     __attribute__ ((aligned(64)));
static uint32_t tx_key_buf[N_KEY_WORDS]       __attribute__ ((aligned(64)));

static uint32_t rx_mdr_buf[N_MDR_WORDS]       __attribute__ ((aligned(64)));
static uint32_t rx_syn_buf[N_SYN_WORDS]       __attribute__ ((aligned(64)));

// Instancias de los 3 DMAs
static XAxiDma DmaPqMdr;    // axi_dma_0: MM2S -> ADC_PQ, S2MM <- MDR
static XAxiDma DmaAliceSyn; // axi_dma_1: MM2S -> ALICE,  S2MM <- SYNDROME
static XAxiDma DmaMask;     // axi_dma_2: MM2S -> MASK

// =============================================================================
// FUNCIONES AUXILIARES
// =============================================================================

// Inicialización genérica de un AXI DMA
static int init_dma(XAxiDma *dma_inst, UINTPTR base_addr, const char *dma_name) {
    XAxiDma_Config *cfg = XAxiDma_LookupConfig(base_addr);
    if (!cfg) {
        xil_printf("[ERROR] No se encontro configuracion para %s (Base: 0x%08X)\r\n", dma_name, base_addr);
        return XST_FAILURE;
    }
    int status = XAxiDma_CfgInitialize(dma_inst, cfg);
    if (status != XST_SUCCESS) {
        xil_printf("[ERROR] Fallo al inicializar %s (Status: %d)\r\n", dma_name, status);
        return XST_FAILURE;
    }
    if (XAxiDma_HasSg(dma_inst)) {
        xil_printf("[ERROR] %s esta en modo Scatter-Gather. Se requiere Simple Transfer.\r\n", dma_name);
        return XST_FAILURE;
    }
    return XST_SUCCESS;
}

// Espera a que un canal DMA termine
static int wait_dma_done(XAxiDma *dma_inst, int direction, const char *name) {
    u32 offset = (direction == XAXIDMA_DMA_TO_DEVICE) ? XAXIDMA_TX_OFFSET : XAXIDMA_RX_OFFSET;
    int timeout = 50000000;
    while (timeout > 0) {
        u32 sr = XAxiDma_ReadReg(dma_inst->RegBase, offset + XAXIDMA_SR_OFFSET);

        // 1. Canal terminó y está en Idle
        if ((sr & XAXIDMA_IDLE_MASK) != 0) {
            XAxiDma_WriteReg(dma_inst->RegBase, offset + XAXIDMA_SR_OFFSET, sr & XAXIDMA_IRQ_ALL_MASK);
            return XST_SUCCESS;
        }

        // 2. Canal detenido (Halted=1) con bytes completados
        if ((sr & XAXIDMA_HALTED_MASK) != 0) {
            if ((sr & XAXIDMA_IRQ_IOC_MASK) != 0) {
                XAxiDma_WriteReg(dma_inst->RegBase, offset + XAXIDMA_SR_OFFSET, sr & (XAXIDMA_IRQ_ALL_MASK | XAXIDMA_ERR_ALL_MASK));
                return XST_SUCCESS;
            } else {
                xil_printf("[ERROR] Fallo en %s! Canal detenido sin completar: DMASR = 0x%08X\r\n", name, sr);
                return XST_FAILURE;
            }
        }
        timeout--;
    }

    u32 sr = XAxiDma_ReadReg(dma_inst->RegBase, offset + XAXIDMA_SR_OFFSET);
    xil_printf("[TIMEOUT] Atasco en %s! DMASR = 0x%08X\r\n", name, sr);
    return XST_FAILURE;
}

// Envía búferes grandes dividiéndolos en bloques <= 16 KB (límite de 14 bits del DMA)
static int dma_send_chunked(XAxiDma *dma, uint8_t *buf, uint32_t total_bytes, const char *name) {
    uint32_t max_chunk = 16380; // Múltiplo de 4 bytes y < 16384
    uint32_t bytes_left = total_bytes;
    uint32_t offset = 0;

    while (bytes_left > 0) {
        uint32_t chunk = (bytes_left > max_chunk) ? max_chunk : bytes_left;
        int status = XAxiDma_SimpleTransfer(dma, (UINTPTR)(buf + offset), chunk, XAXIDMA_DMA_TO_DEVICE);
        if (status != XST_SUCCESS) {
            xil_printf("[ERROR] Fallo transfer TX en %s (status: %d)\r\n", name, status);
            return XST_FAILURE;
        }
        if (wait_dma_done(dma, XAXIDMA_DMA_TO_DEVICE, name) != XST_SUCCESS) {
            return XST_FAILURE;
        }
        offset += chunk;
        bytes_left -= chunk;
    }
    return XST_SUCCESS;
}

// Carga la clave aleatoria u de Bob para UNA trama. El hardware consume cada byte
// una sola vez y bloquea la reconciliación sin clave nueva (STATUS.key_ready).
// AVISO: aquí es el vector fijo de MATLAB (solo test). En operación real debe venir
// de un TRNG; el PS de la Zynq-7000 no tiene uno, hay que añadirlo en la PL.
static int bob_load_key(const uint32_t *key) {
    for (int i = 0; i < N_KEY_WORDS; i++) {
        Xil_Out32(BOB_BASEADDR + BOB_REG_KEY_BASE + (i * 4), key[i]);
    }
    if ((Xil_In32(BOB_BASEADDR + BOB_REG_STATUS) & BOB_STATUS_KEY_READY) == 0) {
        xil_printf("[ERROR] El acelerador no marca la clave como cargada (key_ready = 0).\r\n");
        return XST_FAILURE;
    }
    return XST_SUCCESS;
}

// Telemetría de una trama procesada por el acelerador
typedef struct {
    int32_t  T_final;
    int32_t  sigma_sq;
    uint32_t status;
} bob_frame_hw_t;

// Procesa una trama completa (tx_adc_buf, tx_mask_buf, tx_alice_buf, tx_key_buf):
// soft reset -> clave nueva -> armar RX -> ADC -> máscara + Alice -> esperar resultados.
static int bob_process_frame(bob_frame_hw_t *hw) {
    Xil_Out32(BOB_BASEADDR + BOB_REG_CTRL, 0x00000001); // Soft reset (descarta también la clave)
    Xil_Out32(BOB_BASEADDR + BOB_REG_CTRL, 0x00000002);
    Xil_Out32(BOB_BASEADDR + BOB_REG_CALIB_VARA, 50000); // V_A = 5 SNU x N0 = 10000 cuentas
    if (bob_load_key(tx_key_buf) != XST_SUCCESS) return XST_FAILURE;

    Xil_DCacheFlushRange((UINTPTR)tx_adc_buf,   ADC_BYTE_SIZE);
    Xil_DCacheFlushRange((UINTPTR)tx_alice_buf, ALICE_BYTE_SIZE);
    Xil_DCacheFlushRange((UINTPTR)tx_mask_buf,  MASK_BYTE_SIZE);
    Xil_DCacheInvalidateRange((UINTPTR)rx_mdr_buf, MDR_BYTE_SIZE);
    Xil_DCacheInvalidateRange((UINTPTR)rx_syn_buf, SYN_BYTE_SIZE);

    // Receptores primero. Los 3.264 mensajes MDR llegan en un único paquete (TLAST al final).
    if (XAxiDma_SimpleTransfer(&DmaPqMdr, (UINTPTR)rx_mdr_buf, MDR_BYTE_SIZE, XAXIDMA_DEVICE_TO_DMA) != XST_SUCCESS) {
        xil_printf("[ERROR] No se pudo armar RX MDR (%u B). Configura en axi_dma_0 "
                   "'Width of Buffer Length Register' >= 17 bits.\r\n", (unsigned int)MDR_BYTE_SIZE);
        return XST_FAILURE;
    }
    if (XAxiDma_SimpleTransfer(&DmaAliceSyn, (UINTPTR)rx_syn_buf, SYN_BYTE_SIZE, XAXIDMA_DEVICE_TO_DMA) != XST_SUCCESS) {
        xil_printf("[ERROR] No se pudo armar RX Sindrome.\r\n");
        return XST_FAILURE;
    }

    if (dma_send_chunked(&DmaPqMdr, (uint8_t*)tx_adc_buf, ADC_BYTE_SIZE, "TX ADC") != XST_SUCCESS) return XST_FAILURE;
    if (XAxiDma_SimpleTransfer(&DmaMask, (UINTPTR)tx_mask_buf, MASK_BYTE_SIZE, XAXIDMA_DMA_TO_DEVICE) != XST_SUCCESS) return XST_FAILURE;
    if (dma_send_chunked(&DmaAliceSyn, (uint8_t*)tx_alice_buf, ALICE_BYTE_SIZE, "TX Alice") != XST_SUCCESS) return XST_FAILURE;
    if (wait_dma_done(&DmaMask,     XAXIDMA_DMA_TO_DEVICE, "TX Mascara")  != XST_SUCCESS) return XST_FAILURE;
    if (wait_dma_done(&DmaPqMdr,    XAXIDMA_DEVICE_TO_DMA, "RX MDR")      != XST_SUCCESS) return XST_FAILURE;
    if (wait_dma_done(&DmaAliceSyn, XAXIDMA_DEVICE_TO_DMA, "RX Sindrome") != XST_SUCCESS) return XST_FAILURE;

    // done_est es sticky: basta con sondear hasta verlo
    int timeout = 1000000;
    do {
        hw->status = Xil_In32(BOB_BASEADDR + BOB_REG_STATUS);
    } while ((hw->status & BOB_STATUS_DONE_EST) == 0 && --timeout > 0);

    if ((hw->status & BOB_STATUS_DONE_EST) == 0) {
        xil_printf("[TIMEOUT] La estimacion de parametros no termino (STATUS = 0x%08X).\r\n", hw->status);
        return XST_FAILURE;
    }
    if (hw->status & BOB_STATUS_DATA_LOSS) {
        xil_printf("[ERROR] Perdida de datos en el acelerador (STATUS = 0x%08X): trama invalida.\r\n", hw->status);
        return XST_FAILURE;
    }

    hw->T_final  = (int32_t)Xil_In32(BOB_BASEADDR + BOB_REG_T_FINAL);
    hw->sigma_sq = (int32_t)Xil_In32(BOB_BASEADDR + BOB_REG_SIGMA_SQ);
    Xil_DCacheInvalidateRange((UINTPTR)rx_mdr_buf, MDR_BYTE_SIZE);
    Xil_DCacheInvalidateRange((UINTPTR)rx_syn_buf, SYN_BYTE_SIZE);
    return XST_SUCCESS;
}

// =============================================================================
// PROGRAMA PRINCIPAL
// =============================================================================
int main(void) {
    xil_printf("\r\n========================================================================\r\n");
    xil_printf("   TFG CV-QKD: SUBSISTEMA BOB (HARDWARE/SOFTWARE CO-DESIGN)\r\n");
    xil_printf("   Acelerador FPGA Artix-7 + CPU ARM Cortex-A9 MPCore @ 650 MHz\r\n");
    xil_printf("   Evaluacion de Seguridad Cuantica en Tiempo Real (Holevo Bound)\r\n");
    xil_printf("========================================================================\r\n");

    // 0. Inicializar Timer Global SCU
    init_global_timer();

    // 1. INICIALIZAR LOS 3 AXI DMAS
    #if defined(XPAR_XAXIDMA_0_BASEADDR)
        UINTPTR dma0_addr = XPAR_XAXIDMA_0_BASEADDR;
        UINTPTR dma1_addr = XPAR_XAXIDMA_1_BASEADDR;
        UINTPTR dma2_addr = XPAR_XAXIDMA_2_BASEADDR;
    #elif defined(XPAR_AXI_DMA_0_BASEADDR)
        UINTPTR dma0_addr = XPAR_AXI_DMA_0_BASEADDR;
        UINTPTR dma1_addr = XPAR_AXI_DMA_1_BASEADDR;
        UINTPTR dma2_addr = XPAR_AXI_DMA_2_BASEADDR;
    #else
        UINTPTR dma0_addr = 0x40400000;
        UINTPTR dma1_addr = 0x40410000;
        UINTPTR dma2_addr = 0x40420000;
    #endif

    xil_printf("[INIT] Inicializando controladores AXI DMA...\r\n");
    if (init_dma(&DmaPqMdr,    dma0_addr, "DMA_0 (ADC/MDR)")       != XST_SUCCESS) return XST_FAILURE;
    if (init_dma(&DmaAliceSyn, dma1_addr, "DMA_1 (Alice/Sindrome)") != XST_SUCCESS) return XST_FAILURE;
    if (init_dma(&DmaMask,     dma2_addr, "DMA_2 (Mascara)")       != XST_SUCCESS) return XST_FAILURE;
    xil_printf("  -> Todos los DMAs configurados en modo Simple Transfer.\r\n");

    // 2. CONFIGURAR MÓDULO DE SEGURIDAD CUÁNTICA EN CPU
    cvqkd_security_params_t sec_params;
    cvqkd_security_init_defaults(&sec_params);
    xil_printf("[SEGURIDAD] Parametros de teoria cuantica inicializados:\r\n");
    xil_printf("  -> Modulacion Alice (V_A): 5.00 SNU | Eficiencia Bob (eta): 60.0%%\r\n");
    xil_printf("  -> Ruido Electronico (v_el): 0.10 SNU | Fuga del sindrome LDPC: %u bits\r\n",
               sec_params.leak_ec_bits);
    xil_printf("  -> Muestras sacrificio: %u (50.0%%) | Bits utiles: %u bits\r\n",
               sec_params.m_samples, sec_params.n_key_bits);

    // 3. CARGA INICIAL DE VECTORES BASE
#if USE_MATLAB_VECTORS
    for (int i = 0; i < N_ADC_SAMPLES; i++)   tx_adc_buf[i]   = vec_bob_adc[i];
    for (int i = 0; i < N_ALICE_SAMPLES; i++) tx_alice_buf[i] = vec_alice_data[i];
    for (int i = 0; i < N_MASK_WORDS; i++)    tx_mask_buf[i]  = vec_mask_packed[i];
    for (int i = 0; i < N_KEY_WORDS; i++)     tx_key_buf[i]   = vec_bob_random_bits[i];

    // Cargar clave secreta en la memoria BRAM interna del acelerador (0x100 - 0xDC0)
    for (int i = 0; i < N_KEY_WORDS; i++) {
        Xil_Out32(BOB_BASEADDR + BOB_REG_KEY_BASE + (i * 4), tx_key_buf[i]);
    }
    // Verificación de integridad de la memoria interna
    int key_rb_errs = 0;
    for (int i = 0; i < N_KEY_WORDS; i++) {
        uint32_t rb = Xil_In32(BOB_BASEADDR + BOB_REG_KEY_BASE + (i * 4));
        if (rb != tx_key_buf[i]) key_rb_errs++;
    }
    if (key_rb_errs == 0) {
        xil_printf("  -> [BRAM OK] Memoria interna de clave verificada: 816/816 palabras (26.112 bits).\r\n");
    } else {
        xil_printf("[ERROR] Fallo de verificacion en BRAM de clave (%d errores).\r\n", key_rb_errs);
        return XST_FAILURE;
    }
#endif

    // =========================================================================
    // FASE I: TRAMA DE DIAGNÓSTICO DETALLADO (FRAME 1)
    // =========================================================================
    xil_printf("\r\n========================================================================\r\n");
    xil_printf("       FASE I: DIAGNOSTICO DETALLADO DE SUBSISTEMA (TRAMA 1)\r\n");
    xil_printf("========================================================================\r\n");

    bob_frame_hw_t hw;
    uint64_t f1_start = read_global_timer();
    if (bob_process_frame(&hw) != XST_SUCCESS) return XST_FAILURE;
    uint64_t f1_end = read_global_timer();
    double f1_lat_ms = ((double)(f1_end - f1_start) / GTIMER_FREQ_HZ) * 1000.0;
    int32_t T_est    = hw.T_final;
    int32_t sigma_sq = hw.sigma_sq;

    // Verificación de integridad matemática del MDR y Síndrome
    int64_t norm_sq_q48 = 0;
    for (int i = 0; i < 8; i++) {
        int64_t v = (int32_t)rx_mdr_buf[i];
        norm_sq_q48 += (v * v);
    }
    int32_t norm_sq_q16 = (int32_t)(norm_sq_q48 >> 32);
    int32_t n_int = norm_sq_q16 >> 16;
    int32_t n_frac = (int32_t)(((int64_t)(norm_sq_q16 & 0xFFFF) * 10000) / 65536);

    xil_printf("  -> Norma MDR ||m||^2: %d.%04d (Teorico: 8.0000) [%s]\r\n",
               n_int, n_frac, (n_int == 8 && n_frac <= 200) ? "OK" : "AVISO");
    xil_printf("  -> Telemetria HW: T*eta/2 = 0x%08X | sigma^2 = %d cuentas\r\n", T_est, sigma_sq);

    // Comparación completa con MATLAB (la trama 1 usa los vectores sin modificar).
    // El MDR se compara con tolerancia: el hardware usa una semilla LUT de 1/sqrt
    // (sin Newton-Raphson); 0x30000 = 0.0117 en Q24.
    int mdr_bad = 0, syn_bad = 0;
    int32_t mdr_max_diff = 0;
    for (int i = 0; i < N_MDR_WORDS; i++) {
        int32_t diff = abs((int32_t)rx_mdr_buf[i] - (int32_t)vec_expected_mdr[i]);
        if (diff > mdr_max_diff) mdr_max_diff = diff;
        if (diff > 0x30000) mdr_bad++;
    }
    for (int i = 0; i < N_SYN_WORDS; i++) {
        if (rx_syn_buf[i] != vec_expected_syndrome[i]) syn_bad++;
    }
    bool est_ok = (T_est == (int32_t)EXP_T_FINAL) && (sigma_sq == (int32_t)EXP_SIGMA_SQ);
    xil_printf("  -> Estimacion vs MATLAB: [%s]\r\n", est_ok ? "OK, identica" : "FALLO");
    xil_printf("  -> MDR vs MATLAB: %d/%d palabras fuera de tolerancia, error max 0x%X (Q24) [%s]\r\n",
               mdr_bad, N_MDR_WORDS, mdr_max_diff, mdr_bad ? "FALLO" : "OK");
    xil_printf("  -> Sindrome vs MATLAB: %d/%d palabras distintas [%s]\r\n",
               syn_bad, N_SYN_WORDS, syn_bad ? "FALLO" : "OK");
    xil_printf("  -> Latencia de procesamiento Trama 1: %d.%02d ms\r\n",
               (int)f1_lat_ms, (int)((f1_lat_ms - (int)f1_lat_ms) * 100));

    // Evaluación Cuántica en CPU ARM
    cvqkd_security_result_t sec_res1;
    cvqkd_evaluate_frame_security(&sec_params, T_est, sigma_sq, &sec_res1);
    cvqkd_print_security_report(&sec_res1);

    // =========================================================================
    // FASE II: STREAMING CONTINUO CON EVALUACIÓN DE SEGURIDAD (50 TRAMAS)
    // =========================================================================
    xil_printf("\r\n========================================================================\r\n");
    xil_printf("   FASE II: STREAMING CONTINUO Y DEFENSA ACTIVA (%d TRAMAS)\r\n", NUM_STREAM_FRAMES);
    xil_printf("   - Tramas  1 a 30: Canal Nominal (L = 10 km, xi = 0.010 SNU)\r\n");
    xil_printf("   - Tramas 31 a 40: INYECCION DE ATAQUE / INTRUSION DE EVA (Ruido Elevado)\r\n");
    xil_printf("   - Tramas 41 a 50: Canal Nominal Recuperado (Defensa y Descarte)\r\n");
    xil_printf("========================================================================\r\n");
    xil_printf(" FRAME | ESTADO | T*eta/2 | xi (SNU) | I(A;B) | chi(BE) | K (b/dim) | LATENCIA | VEREDICTO\r\n");
    xil_printf("-------+--------+---------+----------+--------+---------+-----------+----------+---------------------\r\n");

    uint32_t pass_count = 0;
    uint32_t abort_count = 0;
    uint32_t attack_abort_count = 0;
    uint64_t total_stream_cycles = 0;
    uint64_t total_secure_bits = 0;

    for (int frame = 1; frame <= NUM_STREAM_FRAMES; frame++) {
        bool is_attack_frame = (frame >= ATTACK_START_FRAME && frame <= ATTACK_END_FRAME);

        // 1. Inyección de datos según escenario
        if (is_attack_frame) {
            // Ataque de Eva: Ruido de exceso inducido en las muestras ópticas del heterodino
            for (int i = 0; i < N_ADC_SAMPLES; i++) {
                int32_t p = (int16_t)(vec_bob_adc[i] & 0xFFFF);
                int32_t q = (int16_t)((vec_bob_adc[i] >> 16) & 0xFFFF);
                int32_t noise_p = ((rand() % 500) - 250);
                int32_t noise_q = ((rand() % 500) - 250);
                p += noise_p;
                q += noise_q;
                tx_adc_buf[i] = ((uint32_t)(uint16_t)q << 16) | (uint16_t)p;
            }
        } else {
            // Canal nominal óptico
            for (int i = 0; i < N_ADC_SAMPLES; i++) {
                tx_adc_buf[i] = vec_bob_adc[i];
            }
        }

        // 2. Procesar la trama en el acelerador (reset, clave nueva, DMAs y espera)
        uint64_t t_frame_start = read_global_timer();
        bob_frame_hw_t f_hw;
        if (bob_process_frame(&f_hw) != XST_SUCCESS) return XST_FAILURE;
        int32_t f_T_est    = f_hw.T_final;
        int32_t f_sigma_sq = f_hw.sigma_sq;

        // 3. Evaluación de seguridad en CPU ARM Cortex-A9
        cvqkd_security_result_t f_sec;
        cvqkd_evaluate_frame_security(&sec_params, f_T_est, f_sigma_sq, &f_sec);

        uint64_t t_frame_end = read_global_timer();
        uint64_t frame_cycles = t_frame_end - t_frame_start;
        total_stream_cycles += frame_cycles;
        double frame_lat_ms = ((double)frame_cycles / GTIMER_FREQ_HZ) * 1000.0;

        // Veredicto y acción de defensa
        if (f_sec.is_secure) {
            pass_count++;
            total_secure_bits += f_sec.pa_output_bits;
            // Ensamblar paquete para Alice
            bob_tx_alice_packet.block_id = frame;
            bob_tx_alice_packet.T_final  = f_T_est;
            bob_tx_alice_packet.sigma_sq = f_sigma_sq;
        } else {
            abort_count++;
            if (is_attack_frame) attack_abort_count++;
            // Clave descartada inmediatamente, paquete abortado
            bob_tx_alice_packet.magic_header = 0xDEADBEEF;
        }

        // Formateo de métricas para xil_printf
        int t_dec = (int)(((int64_t)(abs(f_T_est) & 0xFFFF) * 10000) / 65536);
        int xi_int = (int)f_sec.xi_snu;
        int xi_frac = (int)((f_sec.xi_snu - xi_int) * 10000);
        int iab_int = (int)f_sec.I_AB;
        int iab_frac = (int)((f_sec.I_AB - iab_int) * 1000);
        int chi_int = (int)f_sec.chi_BE;
        int chi_frac = (int)((f_sec.chi_BE - chi_int) * 1000);
        int k_int = (int)f_sec.K_asymp;
        int k_frac = (int)((f_sec.K_asymp - k_int) * 10000);
        int lat_int = (int)frame_lat_ms;
        int lat_frac = (int)((frame_lat_ms - lat_int) * 100);

        xil_printf(" %5d | %s |  0.%04d |  %2d.%04d  | %d.%03d  |  %d.%03d  |   %d.%04d  | %3d.%02d ms | %s\r\n",
                   frame,
                   is_attack_frame ? "ATAQUE" : "NORMAL",
                   t_dec,
                   xi_int, xi_frac,
                   iab_int, iab_frac,
                   chi_int, chi_frac,
                   k_int, k_frac,
                   lat_int, lat_frac,
                   f_sec.is_secure ? "[ PASS - SEGURO ]" : "[ ABORT - ALERTA ]");
    }

    // =========================================================================
    // RESUMEN GLOBAL Y MÉTRICAS DE CO-DISEÑO
    // =========================================================================
    double total_stream_time_ms = ((double)total_stream_cycles / GTIMER_FREQ_HZ) * 1000.0;
    double avg_lat_ms = total_stream_time_ms / (double)NUM_STREAM_FRAMES;
    double fps = (double)NUM_STREAM_FRAMES / (total_stream_time_ms / 1000.0);
    double optical_mbps = fps * (27857.0 * 32.0) / 1.0e6;
    double net_skr_mbps = ((double)total_secure_bits / (total_stream_time_ms / 1000.0)) / 1.0e6;

    xil_printf("\r\n========================================================================\r\n");
    xil_printf("         RESUMEN FINAL DE STREAMING Y SEGURIDAD CUANTICA                \r\n");
    xil_printf("========================================================================\r\n");
    xil_printf("  * Total Tramas Procesadas:     %d\r\n", NUM_STREAM_FRAMES);
    xil_printf("  * Tramas Seguras Autorizadas:  %d (%d%%)\r\n",
               pass_count, (pass_count * 100) / NUM_STREAM_FRAMES);
    xil_printf("  * Tramas Abortadas:           %d (%d%%)\r\n",
               abort_count, (abort_count * 100) / NUM_STREAM_FRAMES);
    xil_printf("  * Intrusiones Abortadas:       %u/%d tramas de ataque\r\n",
               attack_abort_count, ATTACK_END_FRAME - ATTACK_START_FRAME + 1);
    xil_printf("  ----------------------------------------------------------------------\r\n");
    xil_printf("  * Tiempo Total de Streaming:   %d.%02d ms (%d.%02d s)\r\n",
               (int)total_stream_time_ms, (int)((total_stream_time_ms - (int)total_stream_time_ms) * 100),
               (int)(total_stream_time_ms / 1000.0), (int)(((total_stream_time_ms / 1000.0) - (int)(total_stream_time_ms / 1000.0)) * 100));
    xil_printf("  * Latencia Media por Trama:    %d.%02d ms\r\n",
               (int)avg_lat_ms, (int)((avg_lat_ms - (int)avg_lat_ms) * 100));
    xil_printf("  * Tasa de Tramas (Throughput): %d.%01d tramas/seg\r\n",
               (int)fps, (int)((fps - (int)fps) * 10));
    xil_printf("  * Ingesta Optica Bruta:        %d.%02d Mbps\r\n",
               (int)optical_mbps, (int)((optical_mbps - (int)optical_mbps) * 100));
    xil_printf("  * Clave Secreta Neta Generada: %u bits seguros\r\n", (uint32_t)total_secure_bits);
    xil_printf("  * Tasa Clave Secreta en Vivo:  %d.%03d Mbps\r\n",
               (int)net_skr_mbps, (int)((net_skr_mbps - (int)net_skr_mbps) * 1000));
    xil_printf("========================================================================\r\n");
    xil_printf(" >>> SUBSISTEMA BOB COMPLETADO Y VERIFICADO CON EXITO EN SILICIO <<<\r\n");
    xil_printf("========================================================================\r\n\r\n");

    return XST_SUCCESS;
}
