# Curva Waterfall de la Reconciliación de Alice (RTL en Simulación)

> **Fecha**: 4 de octubre de 2026  
> **Herramientas**: `tools/waterfall_ldpc.sh` (barrido), `cvqkd_matlab/scripts/plot_waterfall.m` (figura)  
> **Diseño**: RTL de Alice sin cambios desde el commit `cbf8d94` (MDR 8D con $K$ dinámico, LDPC 5G-NR BG1 Min-Sum por capas, 200 iteraciones como máximo)  
> **Simulador**: Vivado Simulator 2025.2

---

## 1. Método

Para cada distancia de fibra y cada semilla, `tb_generador_master.m` genera una trama
nueva con el modelo de canal completo: heterodino, ruido de fase (Wiener de 100 kHz +
acústico de 500 Hz), $\eta = 0{,}6$, $v_{el} = 0{,}1$ SNU, $\xi = 0{,}01$ SNU y
$V_A = 5$ SNU. La transmitancia es $T = 10^{-0{,}02 L}$. El testbench
`tb_alice_post_processing_core` pasa la trama por la RTL de Alice (MDR y LDPC) y compara
la clave reconciliada con la de Bob bit a bit. Una trama cuenta como reconciliada si el
LDPC converge y la clave coincide con la de Bob.

La SNR por dimensión es la nominal del canal,
$\text{SNR} = \frac{T\eta V_A/2}{1 + v_{el} + T\eta\xi/2}$; el ruido de fase residual
la reduce un poco. Con la tasa del código fija, $\beta I_{AB} = 1 - 17\,664/26\,112 =
0{,}3235$ bits/dimensión, la eficiencia de cada punto es
$\beta = 0{,}3235 / \tfrac{1}{2}\log_2(1 + \text{SNR})$.

Se han simulado 10 tramas (de 26.112 bits) por distancia entre 8 y 14 km, 90 en total.
Con 10 tramas la tasa de éxito tiene una resolución del 10 %: la curva sitúa bien el
umbral, pero no mide tasas de error de trama pequeñas. En una prueba previa con una trama
por punto, tampoco convergió ninguna a 16, 18 y 20 km.

---

## 2. Resultados

| Distancia | SNR/dim | $\beta$ | Tramas reconciliadas | Iteraciones: media (mín–máx) | Latencia media de Alice |
|---|---|---|---|---|---|
| 8 km | 0,942 | 0,676 | 10/10 | 8,7 (8–10) | 1,48 ms |
| 10 km | 0,859 | 0,723 | 10/10 | 12,3 (10–15) | 1,64 ms |
| 11 km | 0,820 | 0,749 | 10/10 | 17,4 (13–28) | 1,86 ms |
| 11,5 km | 0,802 | 0,762 | 10/10 | 23,1 (15–45) | 2,11 ms |
| 12 km | 0,783 | 0,775 | 8/10 | 42,6 (19–104) | 4,35 ms |
| 12,5 km | 0,766 | 0,789 | 4/10 | 90,0 (34–193) | 7,93 ms |
| 13 km | 0,748 | 0,803 | 1/10 | 62 (una trama) | 9,25 ms |
| 13,5 km | 0,731 | 0,817 | 0/10 | — | 9,85 ms |
| 14 km | 0,715 | 0,832 | 0/10 | — | 9,85 ms |

Las columnas de tramas e iteraciones son resultados de la simulación; la latencia media
aplica el modelo de la sección 3 a todas las tramas del punto (las que no convergen
cuentan 200 iteraciones).

- **Ninguna clave errónea**: todas las tramas en las que el LDPC convergió dieron
  exactamente la clave de Bob (0 de 68 columnas distintas). El criterio de parada
  (síndrome correcto sin cambios en las decisiones) no ha dado ningún falso positivo.
- **Umbral**: el decodificador reconcilia el 100 % de las tramas hasta 11,5 km
  (SNR 0,80, $\beta = 0{,}76$). Entre 12 y 13 km cae del 80 % al 10 % (codo de la curva),
  y desde 13,5 km (SNR 0,73, $\beta = 0{,}82$) no converge ninguna trama.
- **Iteraciones**: crecen y se dispersan al acercarse al umbral: 8–10 a 8 km,
  10–15 a 10 km y de 34 a 193 a 12,5 km. Una trama de 12,5 km converge en 193
  iteraciones, cerca del límite de 200: en esa zona el límite influye en la tasa de éxito.
- **Punto de trabajo (10 km)**: 10/10 tramas reconciliadas con 12,3 iteraciones de media,
  coherente con la trama de referencia (13 iteraciones en simulación y en placa).

La figura (tasa de éxito y las iteraciones de cada trama reconciliada frente a la SNR) la
genera `plot_waterfall.m` en `build/waterfall/fig_waterfall.pdf`.

---

## 3. Latencia frente a iteraciones

El contador de ciclos del wrapper (registro `0x18`, el mismo que lee el MicroBlaze) se
ha medido en simulación (`tb_cvqkd_alice_axi_wrapper`) con cuatro tramas:

| Iteraciones LDPC | Ciclos medidos | Modelo $27\,561 + 1\,094 \cdot it$ |
|---|---|---|
| 8 (8 km) | 36.313 | 36.313 |
| 13 (trama de referencia; en placa, 41.783) | 41.783 | 41.783 |
| 104 (12 km) | 141.337 | 141.337 |
| 193 (12,5 km) | 238.703 | 238.703 |

La latencia es exactamente de $27\,561$ ciclos más $1\,094$ por iteración: 1,10 ms fijos
(carga del síndrome, MDR de los 3.264 bloques y extracción de la clave) más 43,8 µs por
iteración a 25 MHz. Una trama que agota las 200 iteraciones ocupa al decodificador 9,85 ms. La
columna de latencia media de la tabla aplica este modelo a todas las tramas simuladas,
incluidas las que no convergen.

---

## 4. Consecuencia para la tasa de clave

Con la tasa del código fija, al aumentar la distancia $\beta$ sube y la información de
Eva $\chi_{BE}$ baja, así que la fracción de clave por dimensión crece hasta que el LDPC
deja de converger. La tabla da $K_{\text{finite}}$ calculado con `cvqkd_security.c` (el
módulo de seguridad del firmware de Bob) para un bloque de 1000 tramas con estimaciones
ideales del canal y dos valores del ruido en exceso: el nominal del canal (0,01 SNU) y
el que mide Bob en placa cuando las tramas llevan ruido de fase (0,021 SNU de media,
`2026-10-03_Bob_Clave_Secreta_Bloques.md`, sección 7). Es un cálculo, no una medida. Como
las tramas que no convergen se descartan, la clave por trama enviada es
$(1 - \text{FER}) \cdot K_{\text{finite}}$, con la FER de la simulación (10 tramas por punto).

| Distancia | $K_{\text{finite}}$ con $\xi = 0{,}01$ | $(1-\text{FER}) K_{\text{finite}}$ | $K_{\text{finite}}$ con $\xi = 0{,}021$ | $(1-\text{FER}) K_{\text{finite}}$ |
|---|---|---|---|---|
| 8 km | 0,0107 | 0,0107 | −0,0025 | 0 |
| 10 km | 0,0137 | 0,0137 | 0,0027 | 0,0027 |
| 11 km | 0,0173 | 0,0173 | 0,0071 | 0,0071 |
| 11,5 km | 0,0192 | **0,0192** | 0,0096 | 0,0096 |
| 12 km | 0,0214 | 0,0171 | 0,0125 | **0,0100** |
| 12,5 km | 0,0237 | 0,0095 | 0,0149 | 0,0060 |
| 13 km | 0,0260 | 0,0026 | 0,0178 | 0,0018 |
| 13,5 y 14 km | 0,029 – 0,032 | 0 | 0,021 – 0,024 | 0 |

- Con el ruido en exceso medido (0,021 SNU), el punto de trabajo de 10 km da
  $K_{\text{finite}} \approx 0{,}003$ bits/dimensión, coherente con los dos bloques medidos
  en placa (0,0050 y 0,0012). A 8 km no habría clave: el código tiene demasiada
  redundancia para esa SNR ($\beta = 0{,}68$).
- La clave por trama es máxima entre 11,5 y 12 km: a 11,5 km sería unas 3,5 veces la de
  10 km con todas las tramas reconciliadas (10 de 10 en simulación) y a 11 km, unas 2,6
  veces.
- La latencia de Alice crece con la distancia: 1,64 ms de media a 10 km, 1,86 ms a 11 km
  y 2,11 ms a 11,5 km, frente a los 1,91 ms por trama de Bob. Hasta 11 km Alice no es el
  cuello de botella.
- Con 10 tramas por punto no se puede asegurar una FER pequeña a 11–11,5 km: antes de
  mover el punto de trabajo habría que simular más tramas en esa zona.

---

## 5. Comparación con el barrido de $K$ en placa

El ensayo del 29/09 (`2026-09-29_Curva_Waterfall_Factor_K.md`) variaba un $K$ constante
sobre la misma trama, lo que solo reescala los LLR: no cambia la SNR. Esta curva sí
varía el canal y usa una trama nueva por punto. En la placa, la fase 2 del firmware de
Alice queda como prueba de robustez y latencia: la misma trama 1000 veces con $K$
dinámico. Medido el 04/10/2026: las 1000 dan la clave de la fase 1, con 41.783 ciclos
en todas (ver `2026-09-29_Streaming_Continuo_1000.md`).

---

## 6. Reproducción

```bash
XILINX_VIVADO=~/AMD/Xilin/2025.2/Vivado CVQKD_JOBS=5 tools/waterfall_ldpc.sh
matlab -batch "run('cvqkd_matlab/scripts/plot_waterfall.m')"
```

El barrido completo tarda unas 3 horas con 5 simulaciones en paralelo: una trama que
converge tarda ~2 min y una que agota las 200 iteraciones, ~15–20 min.
