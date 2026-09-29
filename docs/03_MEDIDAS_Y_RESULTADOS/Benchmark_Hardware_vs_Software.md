# Benchmark Comparativo: Acelerador Hardware FPGA vs Software en CPU

> **Plataforma Hardware RTL**: Digilent Nexys Video (Xilinx Artix-7 `XC7A200T-1SBG484C` @ 25 MHz)  
> **Plataforma SoC Embebida**: Xilinx PYNQ-Z2 (ARM Cortex-A9 Dual-Core @ 650 MHz, Baremetal Vitis)  
> **Plataforma PC Escritorio**: Host CPU x86-64 moderna (~4.0 GHz, Linux GCC 16.2.1 `-O3` y Python 3.12)  
> **Algoritmo Evaluado**: Reconciliación 5G-NR QC-LDPC Layered Scaled Min-Sum ($Z=384$, 68 columnas $\times$ 46 filas, $N=26.112\text{ bits}$, $\alpha=0.75$)  
> **Criterio de Convergencia**: 7 iteraciones (coincidencia de clave con Bob: 100.00%, BER residual = 0.0000%)

---

## 🎯 1. Resumen Comparativo de Rendimiento en Silicio

| Plataforma / Arquitectura | Frecuencia de Reloj | Potencia TDP (W) | Latencia Trama ($T_{\text{frame}}$) | Throughput Neto (Mbps) | Tramas / segundo | Speedup vs FPGA ($S$) | Eficiencia Energética ($\text{kbits/J}$) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Python 3.12 (Host PC x86-64)** | $\approx 4.0\text{ GHz}$ | $\sim 65\text{ W}$ | **611.00 ms** | 0.043 Mbps | 1.6 tramas/s | **$492.7\times$ más lento** | 0.66 |
| **ARM Cortex-A9 (PYNQ-Z2 Baremetal)** | **650 MHz** | **$\sim 2.5\text{ W}$** | **111.66 ms** | **0.234 Mbps** | **8.96 tramas/s** | **$\mathbf{90.0\times}$ más lento** | **93.6** |
| **C nativo GCC `-O3` (Host PC x86-64)** | $\approx 4.0\text{ GHz}$ | $\sim 65\text{ W}$ | **5.19 ms** | 5.034 Mbps | 192.7 tramas/s | **$4.18\times$ más lento** | 77.4 |
| **MicroBlaze Softcore (Nexys Video)** | 25 MHz | $\sim 0.3\text{ W}$ | $\sim 2.500\text{ ms}$ | 0.010 Mbps | 0.4 tramas/s | **$> 2.000\times$ más lento** | 35 |
| **Acelerador Hardware RTL (Artix-7 @ 25 MHz)** | **25 MHz** | **$\sim 1.5\text{ W}$** | **1.24 ms** | **21.04 Mbps** | **805.8 tramas/s** | **$\mathbf{1.00\times}$ (Referencia)** | **$\mathbf{14.026}$** |
| *Acelerador Hardware RTL (Escalado @ 100 MHz)* | *100 MHz* | *~2.0 W* | *0.31 ms* | *84.16 Mbps* | *3.225 tramas/s* | **$4.00\times$ más rápido** | **$\mathbf{42.080}$** |

---

## 📊 2. Hallazgos Clave de la Comparativa

### A. FPGA Artix-7 @ 25 MHz vs ARM Cortex-A9 @ 650 MHz (PYNQ-Z2)
* **Speedup Demoledor**: El acelerador RTL en la FPGA es **$\mathbf{90.0\times}$ más rápido** que el procesador físico ARM Cortex-A9 ejecutando código baremetal compilado con `-O3` (1.24 ms vs 111.66 ms por trama).
* **Paradoja de la Frecuencia de Reloj**: El Cortex-A9 opera a **650 MHz**, mientras que la FPGA opera a solo **25 MHz** ($26\times$ menor frecuencia de reloj). A pesar de ello, la FPGA procesa la trama en un tiempo 90 veces menor.
* **Eficiencia por Ciclo (IPC Espacial)**: Normalizando por frecuencia de reloj, el datapath hardware de la FPGA realiza **$\mathbf{2.340\times}$ más trabajo por ciclo de reloj** que el núcleo ARM secuencial ($90.0 \times 26 = 2.340$).
* **Eficiencia Energética**:
  - PYNQ-Z2 Cortex-A9: $0.234\text{ Mbps} / 2.5\text{ W} = \mathbf{93.6\text{ kbits/J}}$ ($279.15\text{ mJ/trama}$).
  - FPGA Artix-7: $21.04\text{ Mbps} / 1.5\text{ W} = \mathbf{14.026\text{ kbits/J}}$ ($1.86\text{ mJ/trama}$).
  - **La FPGA es $\mathbf{149.8\times}$ más eficiente energéticamente que el procesador ARM.**

### B. FPGA Artix-7 @ 25 MHz vs CPU de PC x86-64 @ 4.0 GHz
* **Frecuencia de reloj**: La CPU de escritorio opera a una frecuencia **$160\times$ superior** que la FPGA (4.000 MHz vs 25 MHz).
* **Rendimiento neto**: Incluso contra un procesador moderno de arquitectura superescalar out-of-order x86-64, la FPGA en silicio es **$4.18\times$ más rápida que C compilado con `-O3`** y **$492.7\times$ más rápida que Python**.
* **Eficiencia energética**: La FPGA consume únicamente $\approx 1.5\text{ W}$ frente a los $\approx 65\text{ W}$ del procesador de sobremesa, logrando **$14.026\text{ kbits/J}$ frente a $77.4\text{ kbits/J}$** (**$\mathbf{181.2\times}$ mayor eficiencia energética**).

### C. FPGA Artix-7 vs MicroBlaze Softcore (en la propia FPGA)
* **Ahorro de silicio vs rendimiento**: Implementar la reconciliación cuántica por software en el procesador softcore MicroBlaze requiere más de 2 segundos por trama. El diseño del acelerador RTL dedicado dentro de la misma FPGA ofrece una aceleración de **$\mathbf{> 2.000\times}$**, demostrando que la aceleración hardware en silicio es estrictamente obligatoria para sistemas CV-QKD en tiempo real.

---

## 🔬 3. Arquitectura del Benchmark en C (`benchmark/cvqkd_cpu_benchmark.c`)

El benchmark implementa un decodificador idéntico ciclo a ciclo:
1. **Representación Dispersa de la Matriz Base**:
   - `BG_EDGES[46][19]`: Pares `(columna, desplazamiento)` de la matriz 5G-NR BG1.
2. **Decodificación por Capas (*Layered Decoding*)**:
   - Para cada una de las 46 filas de paridad, se procesan los $Z=384$ nodos en paralelo conceptual.
   - Actualización inmediata de los LLRs a posteriori: $\text{LLR}_{post}[v] \leftarrow \text{LLR}_{post}[v] + (\Delta \text{msg})$.
3. **Scaled Min-Sum con Atenuación $\alpha = 0.75$**:
   - Cálculo en punto fijo: `(mag * 3 + 2) >> 2` con saturación a $\pm 127$.
4. **Detención Temprana (*Early Stopping*)**:
   - Comparación instantánea contra el síndrome o la clave dorada en cada iteración.
5. **Temporización Hardware de Alta Resolución**:
   - En ARM Baremetal: Lectura directa por MMIO del *SCU Global Timer* a 325 MHz (`0xF8F00200` - `0xF8F00208`).
   - En Linux Host: `clock_gettime(CLOCK_MONOTONIC)` con resolución de nanosegundos.

---

## 🚀 4. Guía de Reproducción de los Resultados

### En PC Host (x86-64):
```bash
cd /home/drg/TFG/cvqkd_code/benchmark
make host
./bench_host
```

### En PYNQ-Z2 (ARM Cortex-A9):
Conectar la placa PYNQ-Z2 por cable micro-USB al PC y ejecutar:
```bash
cd /home/drg/TFG/cvqkd_code/benchmark
sudo ./run_pynq_benchmark.py
```
El script utiliza XSDB para inicializar el PS7 del Zynq, descargar el binario `cvqkd_benchmark_pynq_arm.elf` a la DDR y capturar la telemetría por el puerto serie USB-UART a 115.200 baudios.
