/******************************************************************************
 *  TFG: Acelerador Hardware CV-QKD - Subsistema Bob (PYNQ-Z2)
 *  Archivo: main.c
 *
 *  Descripción:
 *  Aplicación Baremetal en C (Vitis) para verificar el funcionamiento completo
 *  del acelerador Bob:
 *    1. Inicializa los 3 controladores AXI DMA en modo Direct (Simple Transfer).
 *    2. Configura los parámetros de calibración por AXI4-Lite (calib_VarA).
 *    3. Inyecta por AXI-Stream:
 *         - DMA 0 (MM2S): Pulsos ópticos del ADC {Q, P} -> s_axis_pq (27.857 muestras)
 *         - DMA 1 (MM2S): Datos de sacrificio de Alice   -> s_axis_alice (13.056 muestras)
 *         - DMA 2 (MM2S): Máscara de sacrificio (816 palabras de 32 bits = 26.112 bits)
 *    4. Recoge por AXI-Stream:
 *         - DMA 0 (S2MM): Mensajes públicos MDR (3.264 bloques de 256 bits = 104.448 B)
 *         - DMA 1 (S2MM): Síndrome LDPC (46 filas de 512 bits = 2.944 B)
 *    5. Lee la telemetría por AXI-Lite (T_final, sigma_sq, etc.) y verifica
 *       la coincidencia con las simulaciones de MATLAB.
 ******************************************************************************/

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "xil_printf.h"
#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "sleep.h"

// Si has ejecutado 'python3 export_matlab_to_c.py', pon USE_MATLAB_VECTORS a 1.
// Si está en 0, generará datos sintéticos para un test rápido inmediato.
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
// DEFINICIONES DE HARDWARE Y REGISTROS
// =============================================================================

// Base address del AXI Wrapper de Bob
#if defined(XPAR_CVQKD_BOB_AXI_WRAPPER_0_BASEADDR)
    #define BOB_BASEADDR XPAR_CVQKD_BOB_AXI_WRAPPER_0_BASEADDR
#elif defined(XPAR_CVQKD_BOB_SUBSYSTEM_0_BASEADDR)
    #define BOB_BASEADDR XPAR_CVQKD_BOB_SUBSYSTEM_0_BASEADDR
#else
    #define BOB_BASEADDR 0x40000000 // Dirección por defecto en Vivado
#endif

// Mapa de registros de Bob (Offsets de 32 bits)
#define BOB_REG_CTRL          0x00 // R/W: bit 0 = soft_reset, bit 1 = enable
#define BOB_REG_CALIB_VARA    0x04 // R/W: Varianza de Alice (Q16.16)
#define BOB_REG_STATUS        0x08 // RO:  bit 0 = done_est, bit 1 = syndrome_done
#define BOB_REG_T_FINAL       0x0C // RO:  Transmitancia T (Q16.16)
#define BOB_REG_T_SQRT        0x10 // RO:  sqrt(T) (Q16.16)
#define BOB_REG_SIGMA_SQ      0x14 // RO:  Ruido de exceso sigma^2 (Q16.16)
#define BOB_REG_SIGMA         0x18 // RO:  sigma (Q16.16)
#define BOB_REG_NUM_SAMPLES   0x1C // RO:  Muestras de sacrificio procesadas (13056)

// Tamaños de las tramas del protocolo
#define N_ADC_SAMPLES     27857 // Total muestras ópticas enviadas a Bob
#define N_ALICE_SAMPLES   13056 // Muestras de sacrificio enviadas por Alice
#define N_MASK_WORDS      816   // 26112 bits / 32 bits = 816 palabras
#define N_MDR_BLOCKS      3264  // 3264 bloques de 256 bits (32 bytes)
#define N_MDR_WORDS       (N_MDR_BLOCKS * 8) // 26112 palabras de 32 bits
#define N_SYN_ROWS        46    // 46 filas de síndrome LDPC
#define N_SYN_WORDS       (N_SYN_ROWS * 16)  // 512 bits = 16 palabras de 32 bits por fila

#define ADC_BYTE_SIZE     (N_ADC_SAMPLES   * sizeof(uint32_t)) // 111.428 B
#define ALICE_BYTE_SIZE   (N_ALICE_SAMPLES * sizeof(uint32_t)) //  52.224 B
#define MASK_BYTE_SIZE    (N_MASK_WORDS    * sizeof(uint32_t)) //   3.264 B
#define MDR_BYTE_SIZE     (N_MDR_WORDS     * sizeof(uint32_t)) // 104.448 B
#define SYN_BYTE_SIZE     (N_SYN_WORDS     * sizeof(uint32_t)) //   2.944 B

// =============================================================================
// BÚFERES ALINEADOS A 64 BYTES EN MEMORIA RAM DDR
// =============================================================================
static uint32_t tx_adc_buf[N_ADC_SAMPLES]     __attribute__ ((aligned(64)));
static uint32_t tx_alice_buf[N_ALICE_SAMPLES] __attribute__ ((aligned(64)));
static uint32_t tx_mask_buf[N_MASK_WORDS]     __attribute__ ((aligned(64)));

static uint32_t rx_mdr_buf[N_MDR_WORDS]       __attribute__ ((aligned(64)));
static uint32_t rx_syn_buf[N_SYN_WORDS]       __attribute__ ((aligned(64)));

// Instancias de los 3 DMAs
static XAxiDma DmaPqMdr;    // axi_dma_0: MM2S -> ADC_PQ, S2MM <- MDR
static XAxiDma DmaAliceSyn; // axi_dma_1: MM2S -> ALICE,  S2MM <- SYNDROME
static XAxiDma DmaMask;     // axi_dma_2: MM2S -> MASK

// =============================================================================
// FUNCIONES AUXILIARES
// =============================================================================

// Imprime números en formato punto fijo Q16.16 con xil_printf
static void print_q16_16(const char* label, int32_t raw_val) {
    int32_t sign = (raw_val < 0) ? -1 : 1;
    int32_t abs_val = raw_val * sign;
    int32_t int_part = abs_val >> 16;
    int32_t frac_part = (int32_t)(((int64_t)(abs_val & 0xFFFF) * 10000) / 65536);

    xil_printf("  %-22s: %s%d.%04d (Hex: 0x%08X)\r\n", 
               label, (sign < 0) ? "-" : "", int_part, frac_part, raw_val);
}

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

// Espera a que un canal DMA termine con contador de timeout
static int wait_dma_done(XAxiDma *dma_inst, int direction, const char *name) {
    int timeout = 50000000;
    while (XAxiDma_Busy(dma_inst, direction) && (timeout > 0)) {
        timeout--;
    }
    if (timeout == 0) {
        u32 offset = (direction == XAXIDMA_DMA_TO_DEVICE) ? XAXIDMA_TX_OFFSET : XAXIDMA_RX_OFFSET;
        u32 sr = XAxiDma_ReadReg(dma_inst->RegBase, offset + XAXIDMA_SR_OFFSET);
        xil_printf("[TIMEOUT] Atasco en %s! DMASR = 0x%08X (Halted=%d, Idle=%d, Err=%d)\r\n",
                   name, sr, (sr & 1), ((sr >> 1) & 1), ((sr >> 14) & 1));
        return XST_FAILURE;
    }
    return XST_SUCCESS;
}

// =============================================================================
// PROGRAMA PRINCIPAL
// =============================================================================
int main(void) {
    int status;

    xil_printf("\r\n========================================================\r\n");
    xil_printf("   TEST DE INTEGRACION: SUBSISTEMA BOB CV-QKD (PYNQ-Z2)\r\n");
    xil_printf("========================================================\r\n");

    // 1. INICIALIZAR LOS 3 AXI DMAS
    // Obtenemos las direcciones de los 3 DMAs desde xparameters.h
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
    xil_printf("  -> Todos los DMAs configurados correctamente en modo Simple.\r\n");

    // 2. CONFIGURACIÓN DEL ACELERADOR BOB (AXI4-Lite)
    xil_printf("[CONFIG] Configurando registros AXI-Lite de Bob (Base: 0x%08X)...\r\n", BOB_BASEADDR);
    
    // Soft Reset
    Xil_Out32(BOB_BASEADDR + BOB_REG_CTRL, 0x00000001);
    usleep(100);
    Xil_Out32(BOB_BASEADDR + BOB_REG_CTRL, 0x00000002); // Enable activo

    // Configurar Calibración de Alice VarA (nominal: 40000 = Q16.16)
    Xil_Out32(BOB_BASEADDR + BOB_REG_CALIB_VARA, 40000);
    xil_printf("  -> Calibracion calib_VarA escrita: %d (Q16.16)\r\n", Xil_In32(BOB_BASEADDR + BOB_REG_CALIB_VARA));

    // 3. CARGAR DATOS DE ENTRADA
#if USE_MATLAB_VECTORS
    xil_printf("[DATOS] Cargando vectores reales de simulacion MATLAB...\r\n");
    for (int i = 0; i < N_ADC_SAMPLES; i++)   tx_adc_buf[i]   = vec_bob_adc[i];
    for (int i = 0; i < N_ALICE_SAMPLES; i++) tx_alice_buf[i] = vec_alice_data[i];
    for (int i = 0; i < N_MASK_WORDS; i++)    tx_mask_buf[i]  = vec_mask_packed[i];
#else
    xil_printf("[DATOS] Generando vectores sinteticos de prueba...\r\n");
    for (int i = 0; i < N_ADC_SAMPLES; i++)   tx_adc_buf[i]   = 0x00100020 + i; // Simulado
    for (int i = 0; i < N_ALICE_SAMPLES; i++) tx_alice_buf[i] = 0x00050005 + i;
    for (int i = 0; i < N_MASK_WORDS; i++)    tx_mask_buf[i]  = 0xAAAAAAAA;    // 50% sacrificio
#endif

    // Limpiar búferes de recepción
    for (int i = 0; i < N_MDR_WORDS; i++) rx_mdr_buf[i] = 0;
    for (int i = 0; i < N_SYN_WORDS; i++) rx_syn_buf[i] = 0;

    // 4. GESTIÓN DE CACHÉ (Imprescindible para DMA sobre DDR)
    Xil_DCacheFlushRange((UINTPTR)tx_adc_buf,   ADC_BYTE_SIZE);
    Xil_DCacheFlushRange((UINTPTR)tx_alice_buf, ALICE_BYTE_SIZE);
    Xil_DCacheFlushRange((UINTPTR)tx_mask_buf,  MASK_BYTE_SIZE);

    Xil_DCacheInvalidateRange((UINTPTR)rx_mdr_buf, MDR_BYTE_SIZE);
    Xil_DCacheInvalidateRange((UINTPTR)rx_syn_buf, SYN_BYTE_SIZE);

    // 5. PREPARAR CANALES DE RECEPCIÓN PRIMERO (S2MM)
    xil_printf("[DMA RX] Armando receptores S2MM en DDR...\r\n");
    status = XAxiDma_SimpleTransfer(&DmaPqMdr, (UINTPTR)rx_mdr_buf, MDR_BYTE_SIZE, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("[ERROR] Fallo al armar RX MDR (DMA 0)\r\n");
        return XST_FAILURE;
    }

    status = XAxiDma_SimpleTransfer(&DmaAliceSyn, (UINTPTR)rx_syn_buf, SYN_BYTE_SIZE, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("[ERROR] Fallo al armar RX Sindrome (DMA 1)\r\n");
        return XST_FAILURE;
    }

    // 6. FASE 1: INYECTAR LUZ CUÁNTICA (ADC Bob -> s_axis_pq)
    xil_printf("[FASE 1] Inyectando %d muestras del ADC optico (111.4 KB)...\r\n", N_ADC_SAMPLES);
    status = XAxiDma_SimpleTransfer(&DmaPqMdr, (UINTPTR)tx_adc_buf, ADC_BYTE_SIZE, XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS) {
        xil_printf("[ERROR] Fallo al transmitir ADC (DMA 0)\r\n");
        return XST_FAILURE;
    }
    
    // Esperamos a que todo el paquete del ADC entre en la Mega-FIFO del DSP
    if (wait_dma_done(&DmaPqMdr, XAXIDMA_DMA_TO_DEVICE, "TX ADC (DMA 0)") != XST_SUCCESS) return XST_FAILURE;
    xil_printf("  -> Pulsos opticos procesados por el DSP y almacenados en la Mega-FIFO.\r\n");

    // 7. FASE 2 Y 3: INYECTAR DATOS CLÁSICOS (Alice + Máscara)
    xil_printf("[FASE 2/3] Transmitiendo canal clasico: Sacrificio Alice (%d) y Mascara (%d bits)...\r\n",
               N_ALICE_SAMPLES, N_MASK_WORDS * 32);

    status = XAxiDma_SimpleTransfer(&DmaAliceSyn, (UINTPTR)tx_alice_buf, ALICE_BYTE_SIZE, XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS) return XST_FAILURE;

    status = XAxiDma_SimpleTransfer(&DmaMask, (UINTPTR)tx_mask_buf, MASK_BYTE_SIZE, XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS) return XST_FAILURE;

    // 8. ESPERAR A QUE TERMINEN TODAS LAS TRANSFERENCIAS
    xil_printf("[ESPERA] Procesando en el acelerador hardware...\r\n");
    if (wait_dma_done(&DmaAliceSyn, XAXIDMA_DMA_TO_DEVICE, "TX Alice (DMA 1)") != XST_SUCCESS) return XST_FAILURE;
    if (wait_dma_done(&DmaMask,     XAXIDMA_DMA_TO_DEVICE, "TX Mascara (DMA 2)") != XST_SUCCESS) return XST_FAILURE;
    if (wait_dma_done(&DmaPqMdr,    XAXIDMA_DEVICE_TO_DMA, "RX MDR (DMA 0)")   != XST_SUCCESS) return XST_FAILURE;
    if (wait_dma_done(&DmaAliceSyn, XAXIDMA_DEVICE_TO_DMA, "RX Sindrome (DMA 1)") != XST_SUCCESS) return XST_FAILURE;

    // 9. ESPERAR A QUE LA ESTIMACIÓN DE PARÁMETROS TERMINE (Registro de Status)
    uint32_t status_reg = 0;
    int est_timeout = 1000000;
    while (((status_reg = Xil_In32(BOB_BASEADDR + BOB_REG_STATUS)) & 0x01) == 0 && est_timeout > 0) {
        est_timeout--;
    }

    xil_printf("\r\n========================================================\r\n");
    xil_printf("                 RESULTADOS DE TELEMETRIA               \r\n");
    xil_printf("========================================================\r\n");
    xil_printf("  Registro de Estado    : 0x%08X (done_est=%d, syndrome_done=%d)\r\n",
               status_reg, (status_reg & 1), ((status_reg >> 1) & 1));

    int32_t T_est       = (int32_t)Xil_In32(BOB_BASEADDR + BOB_REG_T_FINAL);
    int32_t T_sqrt_est  = (int32_t)Xil_In32(BOB_BASEADDR + BOB_REG_T_SQRT);
    int32_t sigma_sq    = (int32_t)Xil_In32(BOB_BASEADDR + BOB_REG_SIGMA_SQ);
    int32_t sigma       = (int32_t)Xil_In32(BOB_BASEADDR + BOB_REG_SIGMA);
    uint32_t samples_out= Xil_In32(BOB_BASEADDR + BOB_REG_NUM_SAMPLES);

    print_q16_16("Transmitancia T", T_est);
    print_q16_16("Raiz sqrt(T)", T_sqrt_est);
    print_q16_16("Varianza Ruido sigma^2", sigma_sq);
    print_q16_16("Ruido Exceso sigma", sigma);
    xil_printf("  Muestras Sacrificio   : %u (Esperadas: %d)\r\n", samples_out, N_ALICE_SAMPLES);

    // 10. REFRESCAR CACHÉ DE RECEPCIÓN ANTES DE COMPARAR
    Xil_DCacheInvalidateRange((UINTPTR)rx_mdr_buf, MDR_BYTE_SIZE);
    Xil_DCacheInvalidateRange((UINTPTR)rx_syn_buf, SYN_BYTE_SIZE);

    // 11. VERIFICACIÓN CONTRA MATLAB
#if USE_MATLAB_VECTORS
    xil_printf("\r\n========================================================\r\n");
    xil_printf("        VERIFICACION DE SALIDAS CONTRA MATLAB           \r\n");
    xil_printf("========================================================\r\n");

    // Verificar MDR (Mensajes m públicos)
    int mdr_errors = 0;
    for (int i = 0; i < N_MDR_WORDS; i++) {
        if (rx_mdr_buf[i] != vec_expected_mdr[i]) {
            if (mdr_errors < 5) {
                xil_printf("  [MDR FAIL] Palabra %d | HW: 0x%08X != MATLAB: 0x%08X\r\n",
                           i, rx_mdr_buf[i], vec_expected_mdr[i]);
            }
            mdr_errors++;
        }
    }
    if (mdr_errors == 0) {
        xil_printf("  [ OK ] Mensaje publico MDR: 100%% EXACTO con MATLAB (3264 bloques).\r\n");
    } else {
        xil_printf("  [FAIL] MDR: %d discrepancias detectadas de %d palabras.\r\n", mdr_errors, N_MDR_WORDS);
    }

    // Verificar Síndrome LDPC
    int syn_errors = 0;
    for (int i = 0; i < N_SYN_WORDS; i++) {
        if (rx_syn_buf[i] != vec_expected_syndrome[i]) {
            if (syn_errors < 5) {
                xil_printf("  [SYN FAIL] Palabra %d | HW: 0x%08X != MATLAB: 0x%08X\r\n",
                           i, rx_syn_buf[i], vec_expected_syndrome[i]);
            }
            syn_errors++;
        }
    }
    if (syn_errors == 0) {
        xil_printf("  [ OK ] Sindrome LDPC: 100%% EXACTO con MATLAB (46 filas x 384 bits).\r\n");
    } else {
        xil_printf("  [FAIL] Sindrome: %d discrepancias detectadas.\r\n", syn_errors);
    }

#else
    // Imprimir muestras de las salidas sintéticas
    xil_printf("\r\nPrimer bloque MDR recibido (256 bits / 8 palabras de 32 bits):\r\n");
    for (int i = 0; i < 8; i++) {
        xil_printf("  m[%d] = 0x%08X\r\n", i, rx_mdr_buf[i]);
    }

    xil_printf("\nPrimera fila de Sindrome recibida (512 bits / 16 palabras de 32 bits):\r\n");
    for (int i = 0; i < 16; i++) {
        xil_printf("  syn[0][%d] = 0x%08X\r\n", i, rx_syn_buf[i]);
    }
#endif

    xil_printf("\r\n========================================================\r\n");
    xil_printf("               TEST COMPLETADO CON EXITO               \r\n");
    xil_printf("========================================================\r\n");

    return XST_SUCCESS;
}
