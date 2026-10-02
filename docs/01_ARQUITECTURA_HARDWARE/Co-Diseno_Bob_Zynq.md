# Arquitectura y Co-Diseño Hardware/Software de Bob (PYNQ-Z2)

> **Subsistema**: Receptor Cuántico Bob (Zynq-7020 SoC)  
> **Plataforma**: PYNQ-Z2 (Xilinx Zynq `XC7Z020-1CLG400C`)  
> **Co-Diseño**: Lógica Programable Artix-7 (100 MHz) + Procesador ARM Cortex-A9 Dual-Core (650 MHz)  
> **Última Actualización**: 29 de septiembre de 2026  

---

## 1. Visión General del Subsistema de Bob

A diferencia de Alice (cuyo rol principal es la decodificación intensiva de canal LDPC a partir de los datos recibidos), **Bob** es el extremo de **medida óptica y preparación cuántica**:
1. Recibe los pulsos ópticos del receptor heterodino (dos detectores balanceados, P y Q) a través de interfaces analógicas de alta velocidad.
2. Extrae y compensa el desfase de portadora utilizando pulsos piloto intercalados (interpolador CORDIC).
3. Realiza la criba de sacrificio (50% de las muestras) para estimar analíticamente los parámetros del canal ($T$ y $\sigma^2$).
4. Genera los bits aleatorios de clave mediante un TRNG/PRNG y realiza la proyección multidimensional 8D (MDR) y el cómputo de síndrome LDPC ($H \cdot b$).
5. **Evalúa en la CPU ARM en tiempo real la Cota de Holevo $\chi(B; E)$** para garantizar que ningún intruso (Eva) haya interceptado información del canal, abortando la clave en caso de anomalía.

```
 +---------------------------------------------------------------------------------------------------+
 |                                       PYNQ-Z2 (ZYNQ-7020)                                         |
 |                                                                                                   |
 |   +-------------------------------------------------------------------------------------------+   |
 |   |                      PROCESSING SYSTEM (PS) - ARM Cortex-A9 @ 650 MHz                     |   |
 |   |                                                                                           |   |
 |   |  - Orquestación AXI-DMA (Simple Transfer 3x)      - Control y Calibración AXI4-Lite       |   |
 |   |  - Generador de Máscara de Criba Dinámica         - Evaluación Seguridad Cuántica:        |   |
 |   |  - Medición SCU Global Timer (325 MHz)              * Holevo Bound chi(B; E)              |   |
 |   |  - Protocolo Ethernet/TCP Bob -> Alice              * Información Mutua I(A; B)           |   |
 |   |  - Defensa Activa: Decisión PASS / ABORT            * Secret Key Rate (Asymp & Finite)    |   |
 |   +-------------------------------------------------------------------------------------------+   |
 |                                                ▲ AXI-Lite / AXI-Stream HP                     |
 |   +-------------------------------------------------------------------------------------------+   |
 |   |                     PROGRAMMABLE LOGIC (PL) - FPGA Artix-7 Logic @ 100 MHz                |   |
 |   |                                                                                           |   |
 |   |  [AXI DMA 0 (MM2S)] ---> Ingesta Muestras Ópticas ADC {Q, P} (27.857 muestras)            |   |
 |   |  [AXI DMA 1 (MM2S)] ---> Muestras de Sacrificio de Alice    (13.056 muestras)            |   |
 |   |  [AXI DMA 2 (MM2S)] ---> Máscara de Sacrificio (50%)        (816 palabras / 26.112 bits)  |   |
 |   |                                                                                           |   |
 |   |  [Estimador DSP Hardware]  ---> Transmitancia T*eta (Q16.16) y Varianza sigma^2 (Hardware) |   |
 |   |  [BRAM Interna de Clave]   ---> 816 palabras de clave retenidas (0x100 - 0xDC0)           |   |
 |   |  [Motor MDR 8D Streaming]  ---> ||m||^2 = 8.0000 exacto (3.264 bloques x 256 bits)        |   |
 |   |  [Generador Síndrome LDPC] ---> Matriz H * b (46 filas x 512 bits)                        |   |
 |   |                                                                                           |   |
 |   |  [AXI DMA 0 (S2MM)] <--- Mensajes Públicos MDR (m) hacia DDR                              |   |
 |   |  [AXI DMA 1 (S2MM)] <--- Síndrome LDPC (s) hacia DDR                                      |   |
 |   +-------------------------------------------------------------------------------------------+   |
 +---------------------------------------------------------------------------------------------------+
```

---

## 2. Partición Hardware / Software

La distribución óptima de tareas aprovecha la aceleración paralela masiva de la FPGA y la precisión aritmética flotante de la CPU:

| Módulo / Función | Dominio | Implementación | Justificación Técnica |
| :--- | :---: | :--- | :--- |
| **Ingesta de Muestras Ópticas** | Hardware | Pipeline AXI4-Stream | Flujo masivo de datos (111.4 KB por trama) inviable por software en tiempo real. |
| **Interpolación de Fase CORDIC** | Hardware | DSP48E1 pipelined | Corrección de fase pulso a pulso a 100 MHz sin intervención de CPU. |
| **Estimación Analítica ($T$, $\sigma^2$)** | Hardware | Acumuladores DSP + Divisor Radix-2 + CORDIC Sqrt | Acumulación de 13.056 productos cruzados $\sum P_A P_B$ en tiempo de streaming. |
| **Proyección MDR 8D** | Hardware | Rotaciones ortogonales de Clifford | Cálculo de 3.264 vectores en $S^7$ con conservación estricta de energía. |
| **Generador de Síndrome $H \cdot b$** | Hardware | Desplazadores circulares paralelos | Operaciones de paridad de matriz dispersa $46 \times 68$ con $Z=384$. |
| **Orquestación de Memoria y DMA** | Software | Controlador Baremetal AXI DMA | Control flexible de transferencias en DDR mediante interrupciones/sondeo. |
| **Evaluación de Seguridad Cuántica** | Software | C flotante (`cvqkd_security.c`) | Funciones trascendentes ($g(x)$, $\log_2$, autovalores simplécticos $4 \times 4$). |
| **Detección de Intrusión (PASS/ABORT)**| Software | CPU ARM Cortex-A9 | Decisión de política de seguridad y descarte preventivo de claves. |

---

## 3. Interfaces de Comunicación PL-PS

### 3.1. Canales AXI DMA (High-Performance AXI_HP)
El subsistema integra **tres controladores AXI DMA** independientes configurados en modo *Direct Register (Simple Transfer)*:
1. **DMA 0 (`axi_dma_0` @ `0x40400000`)**:
   - **MM2S**: Transmite los pulsos ópticos del ADC del receptor heterodino ($27.857 \times 4\text{ B} = 111.428\text{ B}$) divididos en bloques de 16 KB (respetando el límite de 14 bits del DMA).
   - **S2MM**: Recibe los mensajes públicos de reconciliación MDR calculados por Bob.
2. **DMA 1 (`axi_dma_1` @ `0x40410000`)**:
   - **MM2S**: Transmite las muestras de sacrificio reveladas por Alice ($13.056 \times 4\text{ B} = 52.224\text{ B}$).
   - **S2MM**: Recibe el síndrome LDPC generado ($46 \times 64\text{ B} = 2.944\text{ B}$).
3. **DMA 2 (`axi_dma_2` @ `0x40420000`)**:
   - **MM2S**: Transmite la máscara de sacrificio ($816 \times 4\text{ B} = 3.264\text{ B}$).

### 3.2. Bus AXI4-Lite de Control y Memoria Interna
Mapeado en `0x40000000` con espacio de memoria contiguo para registros de estado y memoria interna de clave:
- **0x00 - 0x1C**: Registros de control, calibración y telemetría de canal.
- **0x100 - 0xDC0**: BRAM interna de clave (816 palabras = 26.112 bits). El procesador escribe la clave secreta generada en DDR y la FPGA la consume directamente para modular el MDR y el síndrome.

---

## 4. Medición de Rendimiento Hardware (SCU Global Timer)

Para medir la latencia sin sobrecarga de interrupciones o llamadas del sistema operativo, el software utiliza el **SCU Global Timer** del Cortex-A9:
- Dirección Base: `0xF8F00200`
- Frecuencia: $F_{\text{CPU}} / 2 = 325.0\text{ MHz}$
- Resolución temporal: **3.076 ns por tick**
- La lectura de 64 bits se realiza de forma atómica para evitar desbordamientos del registro inferior.
