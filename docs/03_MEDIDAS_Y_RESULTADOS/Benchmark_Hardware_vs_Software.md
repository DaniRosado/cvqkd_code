# Benchmark Comparativo: Acelerador Hardware FPGA vs Software en CPU

> **Plataforma Hardware RTL**: Digilent Nexys Video (Xilinx Artix-7 `XC7A200T-1SBG484C` @ 25 MHz)  
> **Plataforma SoC Embebida**: Xilinx PYNQ-Z2 (ARM Cortex-A9 Dual-Core @ 650 MHz, Baremetal Vitis)  
> **Plataforma PC Escritorio**: Host CPU x86-64 moderna (~4.0 GHz, Linux GCC 16.2.1 `-O3` y Python 3.12)  
> **Algoritmo Evaluado**: Reconciliación 5G-NR QC-LDPC Layered Scaled Min-Sum ($Z=384$, 68 columnas $\times$ 46 filas, $N=26.112\text{ bits}$, $\alpha=0.75$)  
> **Criterio de Convergencia**: 7 iteraciones (coincidencia de clave con Bob: 100.00%, BER residual = 0.0000%)

---

## 🎯 1. Resumen Comparativo de Rendimiento

| Plataforma / Arquitectura | Frecuencia de Reloj | Potencia TDP (W) | Latencia Trama ($T_{\text{frame}}$) | Throughput Neto (Mbps) | Tramas / segundo | Speedup vs FPGA ($S$) | Eficiencia ($\text{kbits/J}$) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Python 3.12 (Host PC x86-64)** | $\approx 4.0\text{ GHz}$ | $\sim 65\text{ W}$ | **611.00 ms** | 0.043 Mbps | 1.6 tramas/s | **$492.7\times$ más lento** | 0.66 |
| **C nativo GCC `-O3` (Host PC x86-64)** | $\approx 4.0\text{ GHz}$ | $\sim 65\text{ W}$ | **5.19 ms** | 5.034 Mbps | 192.7 tramas/s | **$4.18\times$ más lento** | 77.4 |
| **ARM Cortex-A9 (PYNQ-Z2 Baremetal)** | 650 MHz | $\sim 2.5\text{ W}$ | *(Medición en curso)* | *(Proyectado ~0.7 Mbps)* | *(~25 tramas/s)* | *(~30x más lento)* | ~280 |
| **MicroBlaze Softcore (Nexys Video)** | 25 MHz | $\sim 0.3\text{ W}$ | $\sim 2.500\text{ ms}$ | 0.010 Mbps | 0.4 tramas/s | **$> 2.000\times$ más lento** | 35 |
| **Acelerador Hardware RTL (Artix-7 @ 25 MHz)** | **25 MHz** | **$\sim 1.5\text{ W}$** | **1.24 ms** | **21.04 Mbps** | **805.8 tramas/s** | **$1.00\times$ (Referencia)** | **$\mathbf{14.026}$** |
| *Acelerador Hardware RTL (Escalado @ 100 MHz)* | *100 MHz* | *~2.0 W* | *0.31 ms* | *84.16 Mbps* | *3.225 tramas/s* | **$4.00\times$ más rápido** | **$\mathbf{42.080}$** |

---

## 📊 2. Hallazgos Clave de la Comparativa

### A. FPGA Artix-7 @ 25 MHz vs CPU de PC x86-64 @ 4 GHz
* **Frecuencia de reloj**: La CPU de sobremesa opera a una frecuencia **$160\times$ superior** que la FPGA (4.000 MHz vs 25 MHz).
* **Rendimiento neto**: A pesar de la enorme desventaja de reloj, el acelerador RTL en silicio es **$4.18\times$ más rápido en C optimizado** y **$492.7\times$ más rápido que Python**.
* **Eficiencia energética**: La FPGA consume únicamente $\approx 1.5\text{ W}$ frente a los $\approx 65\text{ W}$ del procesador de sobremesa, logrando **$14.026\text{ kbits/Joule}$ frente a $77.4\text{ kbits/Joule}$** (**$\mathbf{181\times}$ mayor eficiencia energética**).

### B. FPGA Artix-7 vs Procesadores Embebidos (PYNQ ARM y MicroBlaze)
* **MicroBlaze (Softcore en la misma FPGA)**: Al no disponer de unidades SIMD masivas, requiere más de 2 segundos por trama. La aceleración RTL en la misma placa ofrece un incremento de rendimiento de **$\mathbf{> 2.000\times}$**.
* **ARM Cortex-A9 (Hard SoC en PYNQ-Z2)**: Aunque dispone de arquitectura ARMv7 superescalar a 650 MHz con cachés L1/L2, el cuello de botella secuencial en los 121.344 accesos a mensajes y chequeos de paridad limita severamente el throughput frente al bus masivo de 3.072 bits del datapath FPGA.

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

---

## 🚀 4. Guía de Ejecución de Benchmarks

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
