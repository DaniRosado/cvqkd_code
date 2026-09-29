# Medida Experimental: Curva Waterfall y Telemetría de Iteraciones LDPC vs Factor K (SNR)

> **Fecha de ensayo**: 29 de septiembre de 2026  
> **Plataforma**: Digilent Nexys Video (Xilinx Artix-7 `XC7A200T-1SBG484C` @ 25 MHz)  
> **Firmware**: MicroBlaze enlazado con telemetría de iteraciones en `REG_STATUS[15:8]`  
> **Total tramas evaluadas**: 1.000 tramas (10 escalones de SNR $\times$ 100 tramas/escalón)  

---

## 🎯 Objetivo del Ensayo

Verificar experimentalmente en silicio real cómo responde el decodificador 5G-NR QC-LDPC ($N = 26.112$ bits, $R = 46/68 \approx 0.676$) ante la variación del **factor de calibración de canal $K$**, que en CV-QKD gobierna la relación señal a ruido (SNR) en función de la atenuación de la fibra óptica:

$$K \propto \frac{\sqrt{T \eta}}{\sigma^2} = \frac{\sqrt{\eta \cdot 10^{-\alpha L / 10}}}{V_{el} + 1 + \eta T \xi}$$

A menor $K$ (mayor distancia de fibra $L$ o mayor exceso de ruido $\xi$), los LLRs iniciales generados por la Reconciliación Multidimensional (MDR) tienen menor amplitud y mayor incertidumbre, forzando al decodificador LDPC a realizar un mayor número de iteraciones para satisfacer la condición de paridad $H \cdot \hat{b} = s$.

---

## 📊 Resultados Experimentales en Silicio (Tabla Maestra)

Datos capturados ciclo a ciclo directamente desde el puerto serie UART a 9600 baudios:

| Paso | Configuración | Condición Física | Factor $K$ (Q10) | Tasa Éxito | Iters Medias | Latencia Media | Throughput Sostenido | Estado Hex (`REG_STATUS`) |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **1** | **Dinámico (`ram_k`)** | **Canal Nominal** | **$\approx 38$ (12–70)** | **100%** | **7** | **1.24 ms** | **21.04 Mbps** | `0x0000070F` |
| **2** | **Escalar $K=16$** | SNR Estable | 16 | **100%** | **10** | **1.35 ms** | **19.28 Mbps** | `0x00000A0F` |
| **3** | **Escalar $K=15$** | Fibra $\sim 30$ km | 15 | **100%** | **9** | **1.31 ms** | **19.84 Mbps** | `0x0000090F` |
| **4** | **Escalar $K=14$** | Fibra $\sim 35$ km | 14 | **100%** | **10** | **1.35 ms** | **19.28 Mbps** | `0x00000A0F` |
| **5** | **Escalar $K=13$** | Fibra $\sim 40$ km | 13 | **100%** | **11** | **1.39 ms** | **18.77 Mbps** | `0x00000B0F` |
| **6** | **Escalar $K=12$** | Fibra $\sim 45$ km | 12 | **100%** | **11** | **1.39 ms** | **18.77 Mbps** | `0x00000B0F` |
| **7** | **Escalar $K=11$** | Alta Exigencia | 11 | **100%** | **11** | **1.39 ms** | **18.77 Mbps** | `0x00000B0F` |
| **8** | **Escalar $K=10$** | Cerca del Umbral | 10 | **100%** | **13** | **1.46 ms** | **17.81 Mbps** | `0x00000D0F` |
| **9** | **Escalar $K=9$** | Régimen Límite | 9 | **100%** | **17** | **1.61 ms** | **16.15 Mbps** | `0x0000110F` |
| **10** | **Escalar $K=8$** | Borde Waterfall | 8 | **100%** | **52** | **2.92 ms** | **8.91 Mbps** | `0x0000340F` |
| *Ref* | *Escalar $K \le 7$* | *Régimen de Corte* | *7* | *0%* | *200 (MAX)* | *1.25 ms (Timeout)* | — | `0x0000C803` |

---

## 📈 Gráfica Conceptual del Comportamiento Waterfall

```
   Número de Iteraciones LDPC
       ^
    55 |                                                         *  (K=8: 52 iters, 2.92 ms)
    50 |                                                         |
    40 |                                                         |  [Borde de la región Waterfall]
    30 |                                                         |
    20 |                                                   *     |  (K=9: 17 iters, 1.61 ms)
    15 |                                       *     *     |     |  (K=10: 13 iters, 1.46 ms)
    10 |       *     *     *     *     *       |     |     |     |  (K=11..16: 9-11 iters)
     7 | *     |     |     |     |     |       |     |     |     |  (Dinámico: 7 iters, 1.24 ms)
       +------------------------------------------------------------> Factor K (SNR decreciente)
        Dyn   K=16  K=15  K=14  K=13  K=12    K=11  K=10   K=9   K=8  | (K=7: Ruptura / Fallo)
```

---

## 🔬 Discusión Técnica y Conclusiones para la Memoria del TFG

### 1. Cuantificación del Coste Temporal por Iteración
Comparando la latencia en $K=10$ (13 iteraciones, $1.46\text{ ms}$) frente a $K=15$ (9 iteraciones, $1.31\text{ ms}$):
$$\Delta t_{\text{iter}} = \frac{1.46\text{ ms} - 1.31\text{ ms}}{13 - 9} = \frac{0.15\text{ ms}}{4} \approx \mathbf{37.5\ \mu\text{s\ por iteración}}$$

En el reloj de $25\text{ MHz}$ ($40\text{ ns}$ por ciclo):
$$N_{\text{ciclos/iter}} \approx \frac{37.5\ \mu\text{s}}{40\text{ ns}} \approx 937.5\text{ ciclos}$$
Esto concuerda con la arquitectura RTL: 46 filas del Base Graph 1, donde cada fila procesa sus aristas en dos pasadas (lectura + escritura) con una latencia de pipeline de 3 ciclos ($\approx 46 \times (19 + 4) \approx 1.058$ ciclos por iteración completa de la matriz).

### 2. Detección de la Región Waterfall y Límite de Shannon
- Para $K \ge 11$, el número de iteraciones oscila suavemente entre 9 y 11.
- Entre $K=10$ y $K=9$, el decodificador entra en la rodilla de la curva (*waterfall knee*), saltando de 13 a 17 iteraciones.
- En **$K=8$**, se produce un incremento no lineal extremo hacia **52 iteraciones** ($+205\%$ de tiempo de cálculo), manteniendo aún el **100% de éxito**.
- En **$K=7$**, se sobrepasa la capacidad de corrección para este tamaño de bloque: el decodificador alcanza el límite de 200 iteraciones sin converger.

### 3. Justificación de la Reconciliación con $K$ Dinámico
El ensayo demuestra por qué la Reconciliación Multidimensional (MDR) requiere modulación dinámica de $K$:
- Cuando se aplicaron factores escalares elevados ($K \ge 24$) en pruebas preliminares, los bloques de alta energía generaron LLRs saturados en $\pm 127$. En decodificadores Min-Sum no atenuados, este exceso de confianza (*over-confidence bias*) atrapa al decodificador en mínimos locales.
- El **Modo Dinámico** calcula $K_{dyn, i} = \frac{2}{\sigma^2} \|y_i\|$ para cada uno de los 3.264 bloques de forma individual, logrando la convergencia óptima en solo **7 iteraciones**.
