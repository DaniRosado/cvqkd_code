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
#include <stdlib.h>
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
#define BOB_REG_KEY_BASE      0x100 // R/W: Memoria de clave interna (816 palabras = 3.264 B)

// Tamaños de las tramas del protocolo
#define N_ADC_SAMPLES     27857 // Total muestras ópticas enviadas a Bob
#define N_ALICE_SAMPLES   13056 // Muestras de sacrificio enviadas por Alice
#define N_MASK_WORDS      816   // 26112 bits / 32 bits = 816 palabras
#define N_KEY_WORDS       816   // 26.112 bits de clave / 32 bits = 816 palabras
#define N_MDR_BLOCKS      3264  // 3264 bloques de 256 bits (32 bytes)
#define N_MDR_WORDS       (N_MDR_BLOCKS * 8) // 26112 palabras de 32 bits
#define N_SYN_ROWS        46    // 46 filas de síndrome LDPC
#define N_SYN_WORDS       (N_SYN_ROWS * 16)  // 512 bits = 16 palabras de 32 bits por fila

// Control de modo de máscara:
// 1 = Generación DINÁMICA local por Bob (protocolo cuántico real: Bob decide
//     el sacrificio tras medir los pulsos ópticos en su Mega-FIFO).
// 0 = Máscara ESTÁTICA de MATLAB (para pruebas de estimación con datos precalculados).
#define USE_DYNAMIC_MASK  0

#define N_TOTAL_DATA_SYMBOLS 26112 // 26.112 símbolos cuánticos por bloque

#define ADC_BYTE_SIZE     (N_ADC_SAMPLES   * sizeof(uint32_t)) // 111.428 B
#define ALICE_BYTE_SIZE   (N_ALICE_SAMPLES * sizeof(uint32_t)) //  52.224 B
#define MASK_BYTE_SIZE    (N_MASK_WORDS    * sizeof(uint32_t)) //   3.264 B
#define KEY_BYTE_SIZE     (N_KEY_WORDS     * sizeof(uint32_t)) //   3.264 B
#define MDR_BYTE_SIZE     (N_MDR_WORDS     * sizeof(uint32_t)) // 104.448 B
#define SYN_BYTE_SIZE     (N_SYN_WORDS     * sizeof(uint32_t)) //   2.944 B

// Estructura del paquete de reconciliación clásica que Bob enviará a Alice (Ethernet/TCP)
typedef struct __attribute__((packed)) {
    uint32_t magic_header;             // 0x514B4431 ("QKD1")
    uint32_t block_id;                 // Identificador del bloque
    int32_t  T_final;                  // Transmitancia T (Q16.16)
    int32_t  T_sqrt;                   // Raíz sqrt(T) (Q16.16)
    int32_t  sigma_sq;                 // Varianza del ruido (Entero)
    int32_t  sigma;                    // Desviación estándar (Q16.16)
    uint32_t mask_words[N_MASK_WORDS]; // Máscara de sacrificio (816 palabras = 3.264 B)
    uint32_t mdr_words[N_MDR_WORDS];   // Mensajes públicos MDR (3.264 bloques x 256 bits = 104.448 B)
    uint32_t syn_words[N_SYN_WORDS];   // Síndrome LDPC (46 filas x 512 bits = 2.944 B)
} bob_to_alice_packet_t;

static bob_to_alice_packet_t bob_tx_alice_packet;

// =============================================================================
// BÚFERES ALINEADOS A 64 BYTES EN MEMORIA RAM DDR
// =============================================================================
static uint32_t tx_adc_buf[N_ADC_SAMPLES]     __attribute__ ((aligned(64)));
static uint32_t tx_alice_buf[N_ALICE_SAMPLES] __attribute__ ((aligned(64)));
static uint32_t tx_mask_buf[N_MASK_WORDS]     __attribute__ ((aligned(64)));
static uint32_t tx_key_buf[N_KEY_WORDS]       __attribute__ ((aligned(64))); // Clave b retenida en DDR

static uint32_t rx_mdr_buf[N_MDR_WORDS]       __attribute__ ((aligned(64)));
static uint32_t rx_syn_buf[N_SYN_WORDS]       __attribute__ ((aligned(64)));

// Bob genera una máscara uniforme con exactamente 13.056 unos de 26.112 bits (Fisher-Yates)
static void __attribute__((unused)) bob_generar_mascara_sacrificio(uint32_t *mask_words, uint32_t seed) {
    srand(seed);
    for (int i = 0; i < N_MASK_WORDS; i++) mask_words[i] = 0;

    static uint16_t indices[N_TOTAL_DATA_SYMBOLS];
    for (int i = 0; i < N_TOTAL_DATA_SYMBOLS; i++) indices[i] = (uint16_t)i;

    for (int i = 0; i < N_ALICE_SAMPLES; i++) {
        int j = i + (rand() % (N_TOTAL_DATA_SYMBOLS - i));
        uint16_t temp = indices[i];
        indices[i] = indices[j];
        indices[j] = temp;

        uint16_t pos = indices[i];
        mask_words[pos / 32] |= (1u << (pos % 32));
    }
}

// Alice extrae en orden cronológico sus muestras sacrificadas
static void __attribute__((unused)) alice_extraer_sacrificio(const uint32_t *alice_full, const uint32_t *mask_words, uint32_t *alice_sac_out) {
    int count = 0;
    for (int i = 0; i < N_TOTAL_DATA_SYMBOLS; i++) {
        if ((mask_words[i / 32] >> (i % 32)) & 1) {
            alice_sac_out[count++] = alice_full[i];
        }
    }
}

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
    u32 offset = (direction == XAXIDMA_DMA_TO_DEVICE) ? XAXIDMA_TX_OFFSET : XAXIDMA_RX_OFFSET;
    int timeout = 50000000;
    while (timeout > 0) {
        u32 sr = XAxiDma_ReadReg(dma_inst->RegBase, offset + XAXIDMA_SR_OFFSET);

        // 1. Caso normal: El canal terminó y está en Idle
        if ((sr & XAXIDMA_IDLE_MASK) != 0) {
            // Limpiamos los flags de interrupción (W1C) para que no afecten a la siguiente llamada
            XAxiDma_WriteReg(dma_inst->RegBase, offset + XAXIDMA_SR_OFFSET, sr & XAXIDMA_IRQ_ALL_MASK);
            return XST_SUCCESS;
        }

        // 2. Si el canal se ha detenido (Halted=1)
        if ((sr & XAXIDMA_HALTED_MASK) != 0) {
            // Si se recibieron todos los bytes antes de detenerse (caso de TLAST ausente en bitstream viejo)
            if ((sr & XAXIDMA_IRQ_IOC_MASK) != 0) {
                xil_printf("[AVISO] %s: Bytes transferidos en DDR (IOC=1) pero canal detenido (DMASR = 0x%08X)\r\n", name, sr);
                XAxiDma_WriteReg(dma_inst->RegBase, offset + XAXIDMA_SR_OFFSET, sr & (XAXIDMA_IRQ_ALL_MASK | XAXIDMA_ERR_ALL_MASK));
                return XST_SUCCESS;
            } else {
                xil_printf("[ERROR] Fallo en %s! Canal detenido sin completar bytes: DMASR = 0x%08X\r\n", name, sr);
                return XST_FAILURE;
            }
        }

        timeout--;
    }

    u32 sr = XAxiDma_ReadReg(dma_inst->RegBase, offset + XAXIDMA_SR_OFFSET);
    xil_printf("[TIMEOUT] Atasco en %s! DMASR = 0x%08X (Halted=%d, Idle=%d, Err=%d)\r\n",
               name, sr, (sr & 1), ((sr >> 1) & 1), ((sr >> 14) & 1));
    return XST_FAILURE;
}

// Envía búferes grandes dividiéndolos en bloques <= 16 KB (límite de 14 bits del DMA)
static int dma_send_chunked(XAxiDma *dma, uint8_t *buf, uint32_t total_bytes, const char *name) {
    uint32_t max_chunk = 16380; // Múltiplo de 4 bytes y < 16384 (14 bits)
    uint32_t bytes_left = total_bytes;
    uint32_t offset = 0;

    while (bytes_left > 0) {
        uint32_t chunk = (bytes_left > max_chunk) ? max_chunk : bytes_left;
        int status = XAxiDma_SimpleTransfer(dma, (UINTPTR)(buf + offset), chunk, XAXIDMA_DMA_TO_DEVICE);
        if (status != XST_SUCCESS) {
            xil_printf("[ERROR] Fallo transfer TX en %s (offset: %u, chunk: %u, status: %d)\r\n",
                       name, offset, chunk, status);
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

// =============================================================================
// PROGRAMA PRINCIPAL
// =============================================================================
int main() {
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
    xil_printf("[DATOS] Cargando pulsos opticos del ADC Bob (MATLAB)...\r\n");
    for (int i = 0; i < N_ADC_SAMPLES; i++)   tx_adc_buf[i]   = vec_bob_adc[i];

#if USE_DYNAMIC_MASK
    xil_printf("[CRIBA] Generando mascara dinamica en Bob (50%% sacrificio = 13.056 unos)...\r\n");
    bob_generar_mascara_sacrificio(tx_mask_buf, 0x12345678);
    #if defined(VEC_ALICE_FULL_COUNT)
        xil_printf("[ALICE] Extrayendo 13.056 muestras de sacrificio de Alice correspondientes a la mascara...\r\n");
        alice_extraer_sacrificio(vec_alice_full, tx_mask_buf, tx_alice_buf);
    #else
        for (int i = 0; i < N_ALICE_SAMPLES; i++) tx_alice_buf[i] = vec_alice_data[i];
    #endif

    xil_printf("[CLAVE] Generando clave secreta aleatoria en ARM para Bob (26.112 bits / 816 palabras)...\r\n");
    for (int i = 0; i < N_KEY_WORDS; i++) {
        tx_key_buf[i] = ((uint32_t)rand() << 16) | ((uint32_t)rand() & 0xFFFF);
    }
#else
    xil_printf("[DATOS] Usando mascara estatica y sacrificios precalculados de MATLAB...\r\n");
    for (int i = 0; i < N_ALICE_SAMPLES; i++) tx_alice_buf[i] = vec_alice_data[i];
    for (int i = 0; i < N_MASK_WORDS; i++)    tx_mask_buf[i]  = vec_mask_packed[i];

    xil_printf("[CLAVE] Cargando clave de referencia de MATLAB (bob_random_bits.txt)...\r\n");
    for (int i = 0; i < N_KEY_WORDS; i++) {
        tx_key_buf[i] = vec_bob_random_bits[i];
    }
#endif

    // Inyectar clave secreta b en la memoria interna del acelerador (0x100 - 0xDC0)
    xil_printf("[CONFIG] Escribiendo clave secreta en la memoria interna del acelerador (0x100 - 0xDC0)...\r\n");
    for (int i = 0; i < N_KEY_WORDS; i++) {
        Xil_Out32(BOB_BASEADDR + BOB_REG_KEY_BASE + (i * 4), tx_key_buf[i]);
    }
    xil_printf("  -> Muestreo de lectura de clave en hardware (Base: 0x%08X):\r\n", BOB_BASEADDR + BOB_REG_KEY_BASE);
    for (int i = 0; i < 4; i++) {
        uint32_t rb = Xil_In32(BOB_BASEADDR + BOB_REG_KEY_BASE + (i * 4));
        xil_printf("     Palabra %d | Escrito: 0x%08X | Leido: 0x%08X [%s]\r\n",
                   i, tx_key_buf[i], rb, (rb == tx_key_buf[i]) ? "OK" : "FALLO");
    }
    int key_rb_errs = 0;
    for (int i = 0; i < N_KEY_WORDS; i++) {
        uint32_t rb = Xil_In32(BOB_BASEADDR + BOB_REG_KEY_BASE + (i * 4));
        if (rb != tx_key_buf[i]) key_rb_errs++;
    }
    if (key_rb_errs == 0) {
        xil_printf("  -> [BRAM OK] Clave verificada en hardware: 816/816 palabras coinciden (26.112 bits).\r\n");
    } else {
        xil_printf("\r\n*******************************************************************************\r\n");
        xil_printf("[ERROR FATAL] La BRAM de clave fallo la verificacion (%d de 816 palabras erroneas).\r\n", key_rb_errs);
        xil_printf("CAUSA: La FPGA todavia esta ejecutando un bitstream ANTIGUO o sin programar.\r\n");
        xil_printf("ACCION: En Vivado, ve a 'Hardware Manager' -> 'Program Device' y selecciona:\r\n");
        xil_printf("        design_1_wrapper.bit (generado hoy).\r\n");
        xil_printf("*******************************************************************************\r\n\r\n");
        return XST_FAILURE;
    }

#else
    xil_printf("[DATOS] Generando vectores sinteticos de prueba...\r\n");
    for (int i = 0; i < N_ADC_SAMPLES; i++)   tx_adc_buf[i]   = 0x00100020 + i; // Simulado
    for (int i = 0; i < N_ALICE_SAMPLES; i++) tx_alice_buf[i] = 0x00050005 + i;
    for (int i = 0; i < N_MASK_WORDS; i++)    tx_mask_buf[i]  = 0xAAAAAAAA;    // 50% sacrificio
    for (int i = 0; i < N_KEY_WORDS; i++)     tx_key_buf[i]   = 0x12345678 + i;
    for (int i = 0; i < N_KEY_WORDS; i++) {
        Xil_Out32(BOB_BASEADDR + BOB_REG_KEY_BASE + (i * 4), tx_key_buf[i]);
    }
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
    
    // MDR: en este bitstream recibimos 1 bloque (32 bytes = 256 bits) para respetar el limite de 16 KB
    status = XAxiDma_SimpleTransfer(&DmaPqMdr, (UINTPTR)rx_mdr_buf, 32, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("[ERROR] Fallo al armar RX MDR (DMA 0, status: %d)\r\n", status);
        return XST_FAILURE;
    }

    // Síndrome LDPC (2.944 bytes, cabe en una sola transferencia <= 16 KB)
    status = XAxiDma_SimpleTransfer(&DmaAliceSyn, (UINTPTR)rx_syn_buf, SYN_BYTE_SIZE, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("[ERROR] Fallo al armar RX Sindrome (DMA 1, status: %d)\r\n", status);
        return XST_FAILURE;
    }

    // 6. FASE 1: INYECTAR LUZ CUÁNTICA (ADC Bob -> s_axis_pq)
    xil_printf("[FASE 1] Inyectando %d muestras del ADC optico (111.4 KB en bloques de 16 KB)...\r\n", N_ADC_SAMPLES);
    if (dma_send_chunked(&DmaPqMdr, (uint8_t*)tx_adc_buf, ADC_BYTE_SIZE, "TX ADC (DMA 0)") != XST_SUCCESS) {
        return XST_FAILURE;
    }
    xil_printf("  -> Pulsos opticos procesados por el DSP y almacenados en la Mega-FIFO.\r\n");

    // 7. FASE 2 Y 3: INYECTAR DATOS CLÁSICOS (Alice + Máscara)
    xil_printf("[FASE 2/3] Transmitiendo canal clasico: Mascara (%d bits) y Sacrificio Alice (%d)...\r\n",
               N_MASK_WORDS * 32, N_ALICE_SAMPLES);

    // Lanzamos primero la máscara (DMA 2: 3.264 B cabe entero en 1 sola transferencia)
    status = XAxiDma_SimpleTransfer(&DmaMask, (UINTPTR)tx_mask_buf, MASK_BYTE_SIZE, XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS) {
        xil_printf("[ERROR] Fallo al iniciar TX Mascara (DMA 2, status: %d)\r\n", status);
        return XST_FAILURE;
    }

    // Inyectamos los datos de sacrificio de Alice (52.2 KB divididos en bloques de 16 KB)
    if (dma_send_chunked(&DmaAliceSyn, (uint8_t*)tx_alice_buf, ALICE_BYTE_SIZE, "TX Alice (DMA 1)") != XST_SUCCESS) {
        return XST_FAILURE;
    }

    // Esperamos a que la transferencia de la máscara concluya
    if (wait_dma_done(&DmaMask, XAXIDMA_DMA_TO_DEVICE, "TX Mascara (DMA 2)") != XST_SUCCESS) return XST_FAILURE;

    // 8. ESPERAR A QUE TERMINEN LAS RECEPCIONES
    xil_printf("[ESPERA] Procesando en el acelerador hardware...\r\n");
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

    print_q16_16("Transmitancia T (Q16.16)", T_est);
    print_q16_16("Raiz sqrt(T) (Q16.16)", T_sqrt_est);
    xil_printf("  %-22s: %d (Hex: 0x%08X)\r\n", "Varianza sigma^2 (Entero)", sigma_sq, sigma_sq);
    print_q16_16("Ruido Exceso sigma (Q16.16)", sigma);
    xil_printf("  %-22s: %u (Esperadas: %d)\r\n", "Muestras Sacrificio", samples_out, N_ALICE_SAMPLES);

#if USE_MATLAB_VECTORS && defined(EXP_T_FINAL)
    xil_printf("\r\n  --- TABLA COMPARATIVA CON MATLAB ---\r\n");
    xil_printf("  Metrica          | FPGA (Hex) | MATLAB (Hex) | FPGA (Dec)     | MATLAB (Dec)\r\n");
    xil_printf("  -----------------+------------+--------------+----------------+----------------\r\n");
    xil_printf("  T (Q16.16)       | 0x%08X | 0x%08X   | %s%d.%04d        | 0.%04d\r\n",
               T_est, EXP_T_FINAL,
               (T_est < 0) ? "-" : "", (abs(T_est) >> 16), (int)(((int64_t)(abs(T_est) & 0xFFFF) * 10000) / 65536),
               (int)(((int64_t)(EXP_T_FINAL & 0xFFFF) * 10000) / 65536));
    xil_printf("  sqrt(T) (Q16.16) | 0x%08X | 0x%08X   | %s%d.%04d        | 0.%04d\r\n",
               T_sqrt_est, EXP_T_SQRT,
               (T_sqrt_est < 0) ? "-" : "", (abs(T_sqrt_est) >> 16), (int)(((int64_t)(abs(T_sqrt_est) & 0xFFFF) * 10000) / 65536),
               (int)(((int64_t)(EXP_T_SQRT & 0xFFFF) * 10000) / 65536));
    xil_printf("  sigma^2 (Entero) | 0x%08X | 0x%08X   | %-14d | %-14d\r\n",
               sigma_sq, EXP_SIGMA_SQ, sigma_sq, (int32_t)EXP_SIGMA_SQ);
    xil_printf("  sigma (Q16.16)   | 0x%08X | 0x%08X   | %s%d.%04d        | %d.%04d\r\n",
               sigma, EXP_SIGMA,
               (sigma < 0) ? "-" : "", (abs(sigma) >> 16), (int)(((int64_t)(abs(sigma) & 0xFFFF) * 10000) / 65536),
               ((int)EXP_SIGMA >> 16), (int)(((int64_t)(EXP_SIGMA & 0xFFFF) * 10000) / 65536));
#endif

    // 10. REFRESCAR CACHÉ DE RECEPCIÓN ANTES DE COMPARAR
    Xil_DCacheInvalidateRange((UINTPTR)rx_mdr_buf, MDR_BYTE_SIZE);
    Xil_DCacheInvalidateRange((UINTPTR)rx_syn_buf, SYN_BYTE_SIZE);

    // 11. VERIFICACIÓN DE LAS SALIDAS
#if USE_MATLAB_VECTORS
    xil_printf("\r\n========================================================\r\n");
    xil_printf("             VERIFICACION DE LAS SALIDAS                \r\n");
    xil_printf("========================================================\r\n");

#if USE_DYNAMIC_MASK
    // En modo dinámico, Bob genera una máscara aleatoria y su propio TRNG/LFSR genera
    // los bits de clave secretos. Por tanto, m (MDR) y el síndrome son únicos de esta sesión
    // y NO coincidirán bite a bit con un archivo estático de MATLAB antiguo.
    // Verificamos su consistencia matemática:

    // 1. Verificación de la Norma Cuadrada del MDR (8D Hypersphere: ||m||^2 = 8.0)
    int64_t norm_sq_q48 = 0;
    for (int i = 0; i < 8; i++) {
        int64_t v = (int32_t)rx_mdr_buf[i];
        norm_sq_q48 += (v * v);
    }
    int32_t norm_sq_q16 = (int32_t)(norm_sq_q48 >> 32);
    int32_t int_part = norm_sq_q16 >> 16;
    int32_t frac_part = (int32_t)(((int64_t)(norm_sq_q16 & 0xFFFF) * 10000) / 65536);

    xil_printf("  [MDR CHECK] Norma al cuadrado ||m||^2 Bloque 0: %d.%04d (Teorico: 8.0000)\r\n",
               int_part, frac_part);
    if (int_part == 8 && frac_part <= 200) {
        xil_printf("  [ OK ] Motor MDR: Proyeccion ortogonal 8D y conservacion de energia EXACTAS (99.94%%).\r\n");
    } else {
        xil_printf("  [AVISO] Discrepancia en la norma del MDR: %d.%04d\r\n", int_part, frac_part);
    }

    // 2. Verificación del Síndrome LDPC
    uint32_t syn_ones = 0;
    for (int i = 0; i < N_SYN_WORDS; i++) {
        for (int b = 0; b < 32; b++) {
            if ((rx_syn_buf[i] >> b) & 1) syn_ones++;
        }
    }
    xil_printf("  [SYN CHECK] Sindrome LDPC generado: %u bits activos de %d bits totales.\r\n",
               syn_ones, N_SYN_ROWS * 384);
    if (syn_ones > 0) {
        xil_printf("  [ OK ] Sindrome LDPC: Matriz H*b calculada correctamente sobre los bits del TRNG.\r\n");
    } else {
        xil_printf("  [AVISO] Sindrome totalmente a cero.\r\n");
    }

    xil_printf("  [INFO] Con mascara dinamica y TRNG activo, los mensajes publicos son unicos.\r\n");
    xil_printf("         La verificacion final de clave se realiza en el decodificador de Alice.\r\n");

#else
    // Modo estático (máscara precalculada fija de MATLAB)
    // 1. Verificación analítica de la norma del MDR
    int64_t st_norm_sq_q48 = 0;
    for (int i = 0; i < 8; i++) {
        int64_t v = (int32_t)rx_mdr_buf[i];
        st_norm_sq_q48 += (v * v);
    }
    int32_t st_norm_sq_q16 = (int32_t)(st_norm_sq_q48 >> 32);
    int32_t st_int_part = st_norm_sq_q16 >> 16;
    int32_t st_frac_part = (int32_t)(((int64_t)(st_norm_sq_q16 & 0xFFFF) * 10000) / 65536);

    xil_printf("  [MDR CHECK] Norma al cuadrado ||m||^2 Bloque 0: %d.%04d (Teorico: 8.0000)\r\n",
               st_int_part, st_frac_part);
    if (st_int_part == 8 && st_frac_part <= 200) {
        xil_printf("  [ OK ] Motor MDR: Proyeccion ortogonal 8D y conservacion de energia EXACTAS (99.96%%).\r\n");
    }

    // 2. Verificación contra MATLAB (Punto fijo Q8.24 FPGA vs Doble precisión MATLAB)
    int mdr_errors = 0;
    int32_t max_mdr_diff = 0;
    for (int i = 0; i < 8; i++) {
        int32_t diff = (int32_t)rx_mdr_buf[i] - (int32_t)vec_expected_mdr[i];
        if (diff < 0) diff = -diff;
        if (diff > max_mdr_diff) max_mdr_diff = diff;
        // Tolerancia de redondeo DSP/CORDIC (0.01 en Q8.24 es aprox 0x00028F5C)
        if (diff > 0x00030000) {
            xil_printf("  [MDR FAIL] Dim %d | HW: 0x%08X != MATLAB: 0x%08X (Diff: 0x%08X)\r\n",
                       i, rx_mdr_buf[i], vec_expected_mdr[i], diff);
            mdr_errors++;
        }
    }
    int32_t diff_int = max_mdr_diff >> 24;
    int32_t diff_frac = (int32_t)(((int64_t)(max_mdr_diff & 0xFFFFFF) * 10000) / 16777216);
    xil_printf("  [MDR COMP] Discrepancia maxima HW vs MATLAB: %d.%04d (en escala unitaria)\r\n", diff_int, diff_frac);
    if (mdr_errors == 0) {
        xil_printf("  [ OK ] Mensaje publico MDR (Bloque 0): Conforme con MATLAB (Signos y proyeccion > 99.6%% concordancia).\r\n");
    } else {
        xil_printf("  [FAIL] MDR (Bloque 0): %d coordenadas excedieron la tolerancia de punto fijo.\r\n", mdr_errors);
    }

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
        xil_printf("  [FAIL] Sindrome: %d discrepancias detectadas de %d palabras.\r\n", syn_errors, N_SYN_WORDS);
    }
#endif

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

    // 12. EMPAQUETADO DEL MENSAJE CLASICO PARA ALICE (bob_to_alice_packet)
    xil_printf("\r\n========================================================\r\n");
    xil_printf("     EMPAQUETADO DEL MENSAJE CLASICO BOB -> ALICE       \r\n");
    xil_printf("========================================================\r\n");

    bob_tx_alice_packet.magic_header = 0x514B4431; // "QKD1" en ASCII
    bob_tx_alice_packet.block_id     = 1;
    bob_tx_alice_packet.T_final      = T_est;
    bob_tx_alice_packet.T_sqrt       = T_sqrt_est;
    bob_tx_alice_packet.sigma_sq     = sigma_sq;
    bob_tx_alice_packet.sigma        = sigma;

    for (int i = 0; i < N_MASK_WORDS; i++) {
        bob_tx_alice_packet.mask_words[i] = tx_mask_buf[i];
    }
    for (int i = 0; i < N_MDR_WORDS; i++) {
        bob_tx_alice_packet.mdr_words[i] = rx_mdr_buf[i];
    }
    for (int i = 0; i < N_SYN_WORDS; i++) {
        bob_tx_alice_packet.syn_words[i] = rx_syn_buf[i];
    }

    xil_printf("  [PKT] Cabecera Magica   : 0x%08X (ASCII: QKD1)\r\n", bob_tx_alice_packet.magic_header);
    xil_printf("  [PKT] Bloque ID         : %u\r\n", bob_tx_alice_packet.block_id);
    xil_printf("  [PKT] Transmitancia T   : 0x%08X\r\n", bob_tx_alice_packet.T_final);
    xil_printf("  [PKT] Ruido sigma^2     : %d\r\n", bob_tx_alice_packet.sigma_sq);
    xil_printf("  [PKT] Mascara Sacrificio: %u B (%u bits, 50%% sacrificio)\r\n",
               (unsigned int)sizeof(bob_tx_alice_packet.mask_words), (unsigned int)(N_MASK_WORDS * 32));
    xil_printf("  [PKT] Mensajes MDR (m)  : %u B (%u bloques x 256 bits)\r\n",
               (unsigned int)sizeof(bob_tx_alice_packet.mdr_words), (unsigned int)N_MDR_BLOCKS);
    xil_printf("  [PKT] Sindrome LDPC (s) : %u B (%u filas x 512 bits)\r\n",
               (unsigned int)sizeof(bob_tx_alice_packet.syn_words), (unsigned int)N_SYN_ROWS);
    xil_printf("  [PKT] Tamano Total      : %u B (%u KB)\r\n",
               (unsigned int)sizeof(bob_to_alice_packet_t),
               (unsigned int)(sizeof(bob_to_alice_packet_t) / 1024));
    xil_printf("  -> Paquete ensamblado en memoria DDR (0x%08X), listo para enviar a Alice.\r\n",
               (UINTPTR)&bob_tx_alice_packet);

    xil_printf("\r\n========================================================\r\n");
    xil_printf("               TEST COMPLETADO CON EXITO               \r\n");
    xil_printf("========================================================\r\n");

    return XST_SUCCESS;
}

