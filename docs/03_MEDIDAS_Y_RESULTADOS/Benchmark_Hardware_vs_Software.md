# Benchmark Comparativo: Acelerador Hardware FPGA vs Software en CPU

> **Plataforma Hardware**: Digilent Nexys Video (Xilinx Artix-7 `XC7A200T-1SBG484C` @ 25 MHz)  
> **Plataforma Software**: CPU x86-64 Intel/AMD moderna (Python 3.12, Decodificador Min-Sum escalado vectorizado)  
> **Tamaño de Trama**: 26.112 bits ($Z=384$, 68 columnas $\times$ 46 filas)  

---

## 🎯 Resumen Comparativo de Rendimiento

| Métrica | Decodificador Software (Python) | Acelerador Hardware FPGA (Silicio) | Ganancia / Speedup |
| :--- | :---: | :---: | :---: |
| **Tiempo de Decodificación (7 iters)** | **611.0 ms** | **1.24 ms** | **$\mathbf{492.7\times}$** |
| **Tiempo de Decodificación (Teórico a 100 MHz)** | 611.0 ms | $\approx 0.31\text{ ms}$ | **$\mathbf{1.970\times}$** |
| **Throughput de Reconciliación** | **0.042 Mbps** (42.7 kbps) | **21.04 Mbps** | **$\mathbf{492.7\times}$** |
| **Tramas Procesadas por Segundo** | 1.63 tramas/s | 805 tramas/s | **$\mathbf{493\times}$** |
| **Potencia Térmica Estimada (TDP)** | $\sim 65\text{ W}$ (CPU estándar) | $\sim 1.5\text{ W}$ (FPGA Artix-7) | **$\mathbf{43\times}$ menor consumo** |
| **Eficiencia Energética (bits / Julio)** | $\approx 657\text{ kbits/J}$ | $\approx 14.000\text{ kbits/J}$ | **$\mathbf{21.3\times}$ más eficiente** |

---

## 🔬 ¿Por qué la FPGA pulveriza el rendimiento de la CPU?

1. **Paralelismo Espacial Masivo en el Datapath**:
   - En cada ciclo de reloj, el datapath del LDPC procesa simultáneamente **$Z = 384$ nodos de variable** en paralelo sobre un bus de **3.072 bits** ($384 \times 8\text{ bits}$).
   - En una CPU secuencial o incluso con instrucciones AVX-512, un vector de 384 LLRs debe fragmentarse en múltiples registros y ciclos de instrucción con saltos condicionales y operaciones de carga/almacenamiento en caché.
2. **Cómputo Directo de Min-Sum en Hardware**:
   - Los nodos CNU calculan el primer mínimo ($min_1$), segundo mínimo ($min_2$) y paridad de signo en hardware combinacional sin penalizaciones por ramas condicionales (*branch mispredictions*).
3. **Pipelining Profundo**:
   - El MDR y el decodificador QC-LDPC operan en una arquitectura canalizada que mantiene los multiplicadores DSP48E1 ocupados en cada ciclo de reloj de 25 MHz.
4. **Verificación de Síndrome sin Latencia**:
   - El módulo `syndrome_checker` calcula el XOR de paridad en paralelo a la decodificación. Cuando la clave es correcta, se detiene inmediatamente (*early stopping*) en el ciclo exacto de convergencia, evitando iteraciones innecesarias.
