# Medidas en Placa: Clave Secreta con Evaluación por Bloques (PYNQ-Z2)

> **Fecha**: 3 de octubre de 2026  
> **Plataforma**: PYNQ-Z2 (Zynq-7020), PS a 650 MHz, acelerador de Bob a 71,4 MHz (FCLK0)  
> **Firmware**: `cvqkd_bob/sw/main.c` (commit `2b90a74`)  
> **Modelo de seguridad**: GG02 heterodino, reconciliación inversa, tamaño finito (Leverrier 2010), ver `docs/02_FUNDAMENTOS_TEORICOS/Seguridad_Cuantica_Holevo_GG02.md`

---

## 1. Resumen

| Magnitud | Valor |
|---|---|
| Tramas procesadas | 3000 (3 bloques de 1000) |
| Bloques seguros | 2/3 |
| Bloques con ataque abortados | 1/1 |
| Latencia media por trama (acelerador + DMA + caché) | 1,94 ms |
| Tasa de tramas | 514,7 tramas/s |
| Ingesta óptica bruta | 458,9 Mbps |
| Clave secreta neta | 581 126 bits |
| Tasa de clave secreta en vivo | 99,7 kbps |

Punto de trabajo: bobina de 10 km ($T = 0{,}631$), $\eta = 0{,}6$, $v_{el} = 0{,}1$ SNU, $\xi = 0{,}01$ SNU, $V_A = 5$ SNU, LDPC 5G-NR BG1 de tasa 22/68.

---

## 2. Fase I: trama de MATLAB (verificación bit a bit)

| Comprobación | Resultado |
|---|---|
| Estimación (`T_FINAL = 0x2F72`, `SIGMA_SQ = 20170`) | Idéntica a MATLAB |
| Norma MDR $\lVert m \rVert^2$ en 3264 bloques | 7,9847 – 8,0148 (ideal 8) |
| MDR frente a MATLAB (informativo) | Error máximo 0,0351 (coma fija frente a coma flotante) |
| Síndrome LDPC | 0/736 palabras distintas |
| Latencia | 1,96 ms |

Una trama aislada ($n = 26\,112$ bits) se aborta siempre: $\xi$ de peor caso 0,39 SNU y $K_{\text{finite}} = -0{,}375$ bits/dim. Es el resultado esperado de la corrección de tamaño finito.

---

## 3. Fase II: streaming con seguridad por bloques

Cada trama es una realización nueva del canal generada en el ARM (`synth_frame`, mismo modelo que `tb_generador_master.m` sin ruido de fase). El acelerador procesa cada trama; la CPU promedia la estimación de las 1000 tramas del bloque y evalúa la seguridad una vez, con $m = 13\,056\,000$ muestras y $n = 26\,112\,000$ bits. En las tramas 1101–1110 Eva intercepta y reenvía con heterodino ($\xi = 2$ SNU).

| Bloque | Tramas | $T$ | $\xi$ (SNU) | $\xi$ peor caso | $K_{\text{finite}}$ (bits/dim) | Bits seguros | Veredicto |
|---|---|---|---|---|---|---|---|
| 1 | 1–1000 | 0,6304 | 0,0139 | 0,0251 | 0,0098 | 254 776 | PASS |
| 2 | 1001–2000 (10 atacadas) | 0,6309 | 0,0293 | 0,0406 | −0,0041 | 0 | ABORT |
| 3 | 2001–3000 | 0,6308 | 0,0111 | 0,0223 | 0,0125 | 326 350 | PASS |

- **Estimación**: $T$ coincide con el valor real (0,631) en los tres bloques. El $\xi$ de los bloques sin ataque (0,0139 y 0,0111) está dentro de la fluctuación esperada ($\pm 0{,}004$ con 1000 tramas).
- **Ataque**: atacar solo el 1 % de las tramas eleva el $\xi$ del bloque a 0,0293, como predice el modelo ($0{,}01 + 2 \cdot 10/1000 = 0{,}03$), y basta para abortarlo. En cada trama atacada el hardware mide $\sigma^2 \approx 24\,300$ cuentas, frente a unas 20 450 en las tramas normales (esperado: $+t^2 \xi N_0 = +3\,790$).
- **Tasa de clave**: la tasa en vivo (99,7 kbps) la limita el procesado de la placa (1,94 ms por trama). La tasa de clave por pulso, $K_{\text{finite}} \approx 0{,}01$ bits/dim, equivaldría a unos 20–25 Mbps con un láser de 1 Gbaud.

---

## 4. Latencia

La fase I siempre ha medido unos 1,95 ms. Hasta el commit `bf633a3`, la fase II reutilizaba las muestras de Alice y medía 1,86 ms. Ahora cada trama escribe muestras nuevas de Alice (52 KB), que el vaciado de la caché tiene que escribir en la DDR antes del DMA. Por eso la latencia sube a 1,94 ms, igual que en la fase I. Esta es la cifra realista: en un sistema real cada trama trae datos nuevos.

El tiempo medido es solo el del acelerador (vaciado de caché, DMAs y espera). Quedan fuera la generación sintética de la trama en el ARM y la UART.

---

## 5. Limitaciones

- El canal de la fase II es sintético y no tiene ruido de fase. El DSP de recuperación de fase solo se ejercita con la trama de MATLAB de la fase I.
- La seguridad asume ataques colectivos y un detector de confianza ($\eta$ y $v_{el}$ calibrados). Faltan un generador de números aleatorios verdadero (TRNG), la autenticación del canal clásico y la verificación de la corrección ($\epsilon_{cor}$) con hash.

---

## 6. Repetición con el diseño optimizado (commit `cbf8d94`)

Mismo ensayo con el hardware regenerado tras las optimizaciones (síndrome con un solo
acumulador, FIFO de trama de 32.768 posiciones, estimador con productos de su anchura
real, MDR sin la etapa de copia) y el firmware que envía cada trama en una sola
transferencia DMA:

| Magnitud | Diseño anterior | Diseño optimizado |
|---|---|---|
| Fase I: estimación, síndrome y norma MDR frente a MATLAB | Idénticos | Idénticos |
| Bits seguros de los bloques 1 / 2 / 3 | 254 776 / 0 / 326 350 | 254 776 / 0 / 326 350 |
| Latencia media por trama | 1,94 ms | 1,91 ms |
| Tasa de tramas | 514,7 tramas/s | 521,9 tramas/s |
| Ingesta óptica bruta | 458,9 Mbps | 465,3 Mbps |
| Tasa de clave secreta en vivo | 99,7 kbps | 101,1 kbps |
| Recursos (LUT / FF / BRAM36 / DSP) | 37.690 / 48.309 / 105 / 76 | 27.138 / 30.095 / 73,5 / 52 |

Todas las filas de la fase II (T·η/2 y σ² de las tramas mostradas) coinciden valor a
valor con la ejecución anterior: el diseño optimizado es funcionalmente idéntico en
placa y ocupa entre un 28 % y un 38 % menos.
