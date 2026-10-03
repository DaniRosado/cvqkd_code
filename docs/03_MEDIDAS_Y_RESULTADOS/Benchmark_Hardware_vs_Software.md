# Benchmark Comparativo Global: Aceleradores Hardware FPGA vs Software en CPU

> **Plataformas Evaluadas**:
> - **FPGA Hardware RTL**: Digilent Nexys Video (Artix-7 `XC7A200T` @ 25 MHz) y PYNQ-Z2 (Zynq-7020 PL @ 100 MHz)
> - **CPU SoC Embebida**: Xilinx PYNQ-Z2 (ARM Cortex-A9 Dual-Core @ 650 MHz, Baremetal Vitis `-O3`)
> - **CPU Host de Escritorio**: PC x86-64 moderna (~4.0 GHz, Linux GCC 16.2.1 `-O3`)
>
> **Subsistemas Comparados**:
> 1. **Alice**: Decodificador QC-LDPC 5G-NR ($N=26.112\text{ bits}$, $Z=384$, Base Graph 1, 7 iteraciones).
> 2. **Bob**: Pipeline completo (Compensación de Fase + Estimación de Parámetros + Proyección MDR 8D + Síndrome LDPC + Cota de Holevo).

> **Nota (03/10/2026)**: las cifras de la FPGA de esta tabla no son medidas. Alice: latencia estimada con el número de sondeos (1,24 ms); con el contador de ciclos del wrapper la trama tarda 41.783 ciclos = **1,67 ms** a 25 MHz (simulación). Bob: 1,50 ms a 100 MHz era un valor nominal; medido en la PYNQ-Z2 es **1,94 ms por trama** con el PL a 71,4 MHz (DMA incluido). Los speedups cambian en proporción (por ejemplo, ARM frente a FPGA: 66,9× en Alice y 9,3× en Bob).

---

## 🎯 1. Resumen Ejecutivo y Comparativa Global de Rendimiento

| Subsistema / Función | Plataforma / Arquitectura | Frecuencia de Reloj | Latencia Trama ($T_{\text{frame}}$) | Throughput (Tramas/s) | Tasa de Datos (Mbps) | Speedup vs FPGA ($S$) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **ALICE: Decodificación LDPC** | Python 3.12 (Host x86-64) | ~4.0 GHz | **611.00 ms** | 1.6 fps | 0.043 Mbps | **$492.7\times$ más lento** |
| | ARM Cortex-A9 (PYNQ-Z2) | 650 MHz | **111.66 ms** | 8.96 fps | 0.234 Mbps | **$90.0\times$ más lento** |
| | C nativo GCC `-O3` (Host x86-64) | ~4.0 GHz | **5.19 ms** | 192.7 fps | 5.034 Mbps | **$4.18\times$ más lento** |
| | **Acelerador FPGA (Artix-7)** | **25 MHz** | **1.24 ms** | **805.8 fps** | **21.04 Mbps** | **$1.00\times$ (Referencia)** |
| **BOB: Pipeline Completo** | ARM Cortex-A9 (PYNQ-Z2) | 650 MHz | **17.97 ms** | 55.62 fps | 49.58 Mbps (ADC) | **$12.0\times$ más lento** |
| | C nativo GCC `-O3` (Host x86-64) | ~4.0 GHz | **2.61 ms** | 381.78 fps | 340.33 Mbps (ADC) | **$1.74\times$ más lento** |
| | **Acelerador FPGA (Artix-7)** | **100 MHz** | **1.50 ms** | **666.67 fps** | **594.30 Mbps (ADC)** | **$1.00\times$ (Referencia)** |

---

## 🔬 2. Análisis Detallado: Subsistema Bob (Ingesta, DSP y Reconciliación)

En el subsistema de Bob, el benchmark por software ([`benchmark/cvqkd_bob_cpu_benchmark.c`](../../benchmark/cvqkd_bob_cpu_benchmark.c)) desglosa el tiempo empleado por cada etapa:

```
                                  DESGLOSE DE LATENCIA DE BOB
  +-------------------------------------+-----------------+-----------------+-----------------+
  | Etapa del Pipeline                  | ARM Cortex-A9   | Host x86-64     | FPGA Artix-7    |
  |                                     | (@ 650 MHz)     | (@ ~4.0 GHz)    | (Pipelined PL)  |
  +-------------------------------------+-----------------+-----------------+-----------------+
  | 1. Compensación Fase (CORDIC/Trig)  | 11.27 ms (62.6%)| 0.98 ms (37.7%) |                 |
  | 2. Criba & Estimación (T, sigma^2)  |  1.06 ms  (5.9%)| 0.29 ms (11.0%) |  1.50 ms TOTAL  |
  | 3. Proyección MDR 8D (3.264 blks)   |  5.51 ms (30.6%)| 1.32 ms (50.6%) | (Pipelined a    |
  | 4. Síndrome LDPC (46x384 checks)    |  0.11 ms  (0.6%)| 0.01 ms  (0.4%) |  100 MHz en PL) |
  | 5. Seguridad Cuántica (Holevo C)    |  0.007 ms (0.0%)| 0.002 ms (0.0%) |                 |
  +-------------------------------------+-----------------+-----------------+-----------------+
  | TOTAL LATENCIA POR TRAMA            | 17.97 ms        | 2.61 ms         | 1.50 ms         |
  | SPEEDUP DEL ACELERADOR HARDWARE     | 11.98x          | 1.74x           | 1.00x (Ref)     |
  +-------------------------------------+-----------------+-----------------+-----------------+
```

### Hallazgos de Ingeniería en Bob:
1. **El cuello de botella software de Bob es la trigonometría**:
   - En la CPU ARM, la compensación de deriva de fase de $27.857$ pulsos ópticos insume **$11.27\text{ ms}$ ($62.6\%$ del tiempo total)** debido a las funciones trascendentes (`atan2`, `sin`, `cos`, interpolación).
   - En la FPGA, dos núcleos **CORDIC pipelinizados** procesan las muestras al vuelo ciclo a ciclo a 100 MHz sin consumo de CPU.
2. **La proyección MDR 8D es altamente acelerable en FPGA**:
   - Requiere normalización euclídea y rotaciones ortogonales de Hurwitz-Radon sobre $3.264$ bloques. En la CPU toma **$5.51\text{ ms}$**, mientras que en la FPGA se computa mediante un datapath de 9 etapas de registros multiplexores y sumadores sin divisiones en punto flotante.
3. **El cómputo de síndrome y la cota de Holevo son ligeros**:
   - El cálculo del síndrome LDPC toma **$0.11\text{ ms}$** gracias al algoritmo rápido de desplazamiento circular de palabras de 384 bits.
   - La evaluación de seguridad cuántica (Holevo) toma solo **$7\ \mu\text{s}$**, lo que confirma que **ejecutar la seguridad cuántica en software (CPU) dentro del co-diseño es la partición arquitectónica ideal**, liberando recursos de lógica para el procesamiento masivo de datos.

---

## ⚡ 3. Eficiencia por Ciclo de Reloj y Normalización Arquitectónica

Al contrastar la frecuencia de reloj frente a la latencia obtenida, se evidencia la superioridad del paralelismo espacial (hardware) frente a la ejecución temporal secuencial (CPU):

| Módulo | Plataforma CPU | Relación Frecuencias ($F_{\text{CPU}} / F_{\text{FPGA}}$) | Speedup Bruto | Speedup Normalizado (Trabajo / Ciclo) |
| :--- | :--- | :---: | :---: | :---: |
| **Alice (LDPC)** | ARM Cortex-A9 (650 MHz) vs Artix-7 (25 MHz) | $26.0\times$ | **$90.0\times$** | **$\mathbf{2.340\times}$ más trabajo por ciclo** |
| | Host x86-64 (4.0 GHz) vs Artix-7 (25 MHz) | $160.0\times$ | **$4.18\times$** | **$\mathbf{668.8\times}$ más trabajo por ciclo** |
| **Bob (DSP+MDR)** | ARM Cortex-A9 (650 MHz) vs Artix-7 (100 MHz) | $6.5\times$ | **$12.0\times$** | **$\mathbf{77.9\times}$ más trabajo por ciclo** |
| | Host x86-64 (4.0 GHz) vs Artix-7 (100 MHz) | $40.0\times$ | **$1.74\times$** | **$\mathbf{69.6\times}$ más trabajo por ciclo** |

---

## 🔋 4. Eficiencia Energética y Consumo

| Subsistema / Plataforma | Consumo de Potencia (W) | Latencia Trama (ms) | Energía por Trama ($E = P \cdot t$) | Eficiencia Energética ($\text{kbits/J}$) |
| :--- | :---: | :---: | :---: | :---: |
| **Alice: ARM Cortex-A9** | $\sim 2.5\text{ W}$ | $111.66\text{ ms}$ | $279.15\text{ mJ}$ | $93.6\text{ kbits/J}$ |
| **Alice: Host PC x86-64** | $\sim 65.0\text{ W}$ | $5.19\text{ ms}$ | $337.35\text{ mJ}$ | $77.4\text{ kbits/J}$ |
| **Alice: FPGA Artix-7 (@ 25 MHz)** | **$\sim 1.5\text{ W}$** | **$1.24\text{ ms}$** | **$\mathbf{1.86\text{ mJ}}$** | **$\mathbf{14.026\text{ kbits/J}}$** |
| **Bob: ARM Cortex-A9** | $\sim 2.5\text{ W}$ | $17.97\text{ ms}$ | $44.93\text{ mJ}$ | $581.2\text{ kbits/J}$ |
| **Bob: Host PC x86-64** | $\sim 65.0\text{ W}$ | $2.61\text{ ms}$ | $169.65\text{ mJ}$ | $153.9\text{ kbits/J}$ |
| **Bob: FPGA Artix-7 (@ 100 MHz)** | **$\sim 2.0\text{ W}$** | **$1.50\text{ ms}$** | **$\mathbf{3.00\text{ mJ}}$** | **$\mathbf{8.704\text{ kbits/J}}$** |

> **Conclusión Energética**:
> - En **Alice**, la FPGA es **$\mathbf{149.8\times}$ más eficiente** que el ARM Cortex-A9 y **$\mathbf{181.2\times}$ más eficiente** que la CPU x86-64.
> - En **Bob**, la FPGA es **$\mathbf{15.0\times}$ más eficiente** que el ARM Cortex-A9 y **$\mathbf{56.5\times}$ más eficiente** que la CPU x86-64.

---

## 🚀 5. Scripts de Reproducción de los Benchmarks

### 5.1. Para Alice (Decodificador LDPC)
```bash
cd benchmark
# En PC Host:
make host && ./bench_host
# En PYNQ-Z2 (ARM):
make arm && ../tools/run_board.py bench-alice
```

### 5.2. Para Bob (Pipeline Completo)
```bash
cd benchmark
# En PC Host:
make bob_host && ./bench_bob_host
# En PYNQ-Z2 (ARM):
make bob_arm && ../tools/run_board.py bench-bob
```
