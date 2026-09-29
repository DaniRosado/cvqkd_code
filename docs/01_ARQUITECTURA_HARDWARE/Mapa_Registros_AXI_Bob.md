# Mapa de Registros AXI4-Lite y Memoria de Bob (PYNQ-Z2)

> **Subsistema**: `cvqkd_bob_axi_wrapper`  
> **Plataforma**: PYNQ-Z2 (Zynq-7020)  
> **Dirección Base**: `0x40000000` (mapeada en Vivado Address Editor)  
> **Bus**: AXI4-Lite Slave de 32 bits  

---

## 1. Espacio de Registros de Control y Telemetría (`0x00` – `0x1C`)

| Offset (Hex) | Nombre de Registro | Tipo | Descripción y Formato de Bits |
| :---: | :--- | :---: | :--- |
| `0x00` | `BOB_REG_CTRL` | R/W | **Registro de Control**: <br>• Bit 0: `soft_reset` (1 = reset síncrono de FIFOs y acumuladores). <br>• Bit 1: `enable` (1 = habilita el datapath del subsistema). |
| `0x04` | `BOB_REG_CALIB_VARA` | R/W | **Varianza de Modulación de Alice ($Var(A)$)**: <br>• Formato: Entero en cuentas ADC ($V_A \cdot N_0$). <br>• Valor nominal de calibración: `40000` ($4.0\text{ SNU} \times 10.000\text{ cuentas}$). |
| `0x08` | `BOB_REG_STATUS` | RO | **Registro de Estado**: <br>• Bit 0: `done_est` (1 = estimación de parámetros $T$ y $\sigma^2$ lista). <br>• Bit 1: `syndrome_done` (1 = cómputo de síndrome LDPC completado). <br>• Bits 31:2: Reservados. |
| `0x0C` | `BOB_REG_T_FINAL` | RO | **Transmitancia Neta del Canal ($T \cdot \eta$)**: <br>• Formato: Punto fijo con signo **Q16.16**. <br>• $T_{\text{eta}} = \text{valor} / 65536.0$. Transmitancia física: $T = T_{\text{eta}} / \eta$. |
| `0x10` | `BOB_REG_T_SQRT` | RO | **Raíz Cuadrada de Transmitancia ($\sqrt{T \cdot \eta}$)**: <br>• Formato: Punto fijo con signo **Q16.16**. <br>• Producido por el bloque de división del estimador analítico. |
| `0x14` | `BOB_REG_SIGMA_SQ` | RO | **Varianza Total Observada en Bob ($\sigma_B^2$)**: <br>• Formato: Entero de 32 bits sin signo (cuentas ADC al cuadrado). <br>• En unidades SNU: $\text{Var}_B = \sigma_B^2 / N_0$. |
| `0x18` | `BOB_REG_SIGMA` | RO | **Desviación Estándar ($\sigma_B$)**: <br>• Formato: Punto fijo **Q16.16**. <br>• Calculado mediante CORDIC Sqrt hardware sobre `sigma_sq`. |
| `0x1C` | `BOB_REG_NUM_SAMPLES` | RO | **Muestras de Sacrificio Procesadas**: <br>• Formato: Entero de 32 bits. <br>• Valor esperado al finalizar la trama: `13056` (50% de la trama). |

---

## 2. Memoria BRAM Interna de Clave Secreta (`0x100` – `0xDC0`)

La memoria de clave reside internamente en la lógica programable de Bob y almacena la secuencia de bits generada para cada trama:
- **Rango de Direcciones**: `0x40000100` a `0x40000DC0` (longitud: $3.264\text{ bytes} = 816\text{ palabras de 32 bits}$).
- **Capacidad Total**: $816 \times 32 = \mathbf{26.112\text{ bits de clave}}$.
- **Acceso**:
  - **Escritura desde PS**: El procesador ARM Cortex-A9 escribe las 816 palabras antes de iniciar el streaming.
  - **Lectura en PL**: El motor MDR y el generador de síndrome LDPC leen automáticamente esta memoria byte a byte al procesar las muestras cuánticas.

```c
// Ejemplo de acceso en C (Vitis Baremetal)
#define BOB_BASEADDR     0x40000000
#define BOB_REG_KEY_BASE 0x100
#define N_KEY_WORDS      816

// Cargar 26.112 bits de clave secreta
for (int i = 0; i < N_KEY_WORDS; i++) {
    Xil_Out32(BOB_BASEADDR + BOB_REG_KEY_BASE + (i * 4), tx_key_buf[i]);
}
```

---

## 3. Direccionamiento de Canales DMA AXI-HP

| Instancia | Base Address | Canal | Uso en Protocolo CV-QKD | Ancho de Bus |
| :--- | :---: | :---: | :--- | :---: |
| `axi_dma_0` | `0x40400000` | **MM2S** | Envío de pulsos ópticos del ADC $\{Q, P\}$ (111.4 KB) | 32 bits |
| `axi_dma_0` | `0x40400000` | **S2MM** | Recepción de vectores públicos MDR $m$ (104.4 KB) | 32 bits |
| `axi_dma_1` | `0x40410000` | **MM2S** | Envío de muestras de sacrificio de Alice (52.2 KB) | 32 bits |
| `axi_dma_1` | `0x40410000` | **S2MM** | Recepción de matriz de síndrome LDPC $s$ (2.94 KB) | 32 bits |
| `axi_dma_2` | `0x40420000` | **MM2S** | Envío de máscara de criba de sacrificio (3.26 KB) | 32 bits |
