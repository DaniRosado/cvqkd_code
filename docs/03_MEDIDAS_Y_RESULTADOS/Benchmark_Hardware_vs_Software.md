# Benchmark: Aceleradores FPGA frente a Software en CPU

> **Programas**: `benchmark/cvqkd_cpu_benchmark.c` (Alice: decodificador LDPC) y `benchmark/cvqkd_bob_cpu_benchmark.c` (Bob: cadena completa), en C con `-O3`  
> **CPU**: ARM Cortex-A9 del Zynq-7020 (PYNQ-Z2) a 650 MHz, *baremetal*, temporizador global del SCU; Intel Core i7-8665U del PC (portátil, 1,9 GHz nominales y hasta 4,8 GHz en turbo, Linux, `clock_gettime`)  
> **FPGA**: Alice en la Nexys Video a 25 MHz (contador de ciclos del acelerador); Bob en la PL de la PYNQ-Z2 a 71,4 MHz (DMA incluido)

> **Revisión (04/10/2026)**: la versión anterior de este informe comparaba el tiempo del decodificador en CPU (LDPC solo, 7 iteraciones, trama de septiembre) con una latencia de la FPGA que no estaba medida (1,24 ms) y daba 90× / 4,18× en Alice y 12× / 1,74× en Bob. Además, el "PC de sobremesa a ~4 GHz" es el portátil i7-8665U. Las cifras de abajo son las medidas actuales.

---

## 1. Alice: decodificador LDPC

El programa decodifica una trama fija con el mismo algoritmo que la RTL (*layered scaled min-sum*, α = 0,75) y converge en 7 iteraciones. El trabajo de una iteración no depende de la trama, así que se compara el tiempo por iteración con el de la FPGA, que es de 1.094 ciclos (medido con el contador del acelerador, ver `2026-10-04_Waterfall_LDPC_Simulacion.md`).

| Plataforma | Trama del benchmark (7 iteraciones) | Por iteración | Aceleración de la FPGA |
|---|---|---|---|
| ARM Cortex-A9, 650 MHz (medido el 29/09, mismo programa y datos) | 111,66 ms | 15,95 ms | **364×** |
| Intel Core i7-8665U (medido el 04/10, media de 50 tramas) | 5,02 ms | 0,72 ms | **16,4×** |
| FPGA Artix-7, 25 MHz | — | 43,76 µs | — |

La FPGA reconcilia la trama completa del punto de trabajo (síndrome, MDR, 13 iteraciones y extracción de la clave) en 1,67 ms medidos en placa. Las 13 iteraciones del LDPC solas llevarían unos 207 ms en el ARM y 9,3 ms en el i7.

---

## 2. Bob: cadena completa

El programa ejecuta la compensación de fase, la criba y estimación, el MDR 8D, el síndrome y la evaluación de seguridad sobre la trama de MATLAB (vectores heterodinos actuales). La FPGA hace lo mismo salvo la seguridad, que sigue en el ARM.

| Etapa | ARM Cortex-A9 (04/10) | Intel Core i7-8665U (04/10) |
|---|---|---|
| Compensación de fase | 15,19 ms (69,4 %) | 0,56 ms (41,9 %) |
| Criba y estimación | 1,04 ms (4,7 %) | 0,14 ms (10,6 %) |
| MDR 8D (3.264 bloques) | 5,51 ms (25,2 %) | 0,63 ms (46,9 %) |
| Síndrome LDPC | 0,11 ms (0,5 %) | 5 µs (0,4 %) |
| Seguridad (Holevo) | 8 µs | ~1 µs |
| **Total por trama** | **21,87 ms** | **1,34 ms** |
| FPGA (placa, con DMA) | 1,91 ms: **11,5×** | 1,91 ms: 0,70× |

Medias de 50 tramas. En el ARM, la compensación de fase y el MDR suman el 95 % del tiempo: son las etapas que hace la PL. Frente al ARM, la FPGA es 11,5× más rápida (unas 104 veces más trabajo por ciclo, con la PL a 71,4 MHz frente a 650 MHz). El i7 es más rápido que la PL (1,34 ms frente a 1,91 ms): la PL procesa una muestra por ciclo a 71,4 MHz y el tiempo medido incluye el vaciado de caché y los DMA. El acelerador libera al ARM, que solo evalúa la seguridad (8 µs por bloque).

La cifra del 29/09 (17,97 ms) se midió con los vectores anteriores al modelo heterodino; la compensación de fase es la etapa que ha crecido (11,27 → 15,19 ms). El benchmark usaba además $V_A = 4$ SNU (40.000 cuentas) en lugar de 5: no cambia los tiempos, pero su comprobación de la estimación no coincidía con el hardware. Corregido el 04/10.

---

## 3. Energía (estimación)

No se ha medido la potencia. Estimación de `report_power` de Vivado tras el rutado (sin vectores de actividad): diseño de Alice 1,26 W; Zynq-7020 de Bob 1,74 W, de los que 1,26 W son del PS7. Para el i7 se usa su TDP, 15 W.

| | Potencia | Alice: energía por iteración LDPC | Bob: energía por trama |
|---|---|---|---|
| ARM Cortex-A9 (PS7) | 1,26 W | 20,1 mJ | 27,6 mJ |
| Intel Core i7-8665U | 15 W (TDP) | 10,8 mJ | 20,1 mJ |
| FPGA de Alice | 1,26 W | 55 µJ | — |
| Zynq-7020 de Bob (PS + PL) | 1,74 W | — | 3,32 mJ |

---

## 4. Reproducción

```bash
cd benchmark
make host bob_host && ./bench_host && ./bench_bob_host   # PC
make arm bob_arm                                          # ELF para el ARM
../tools/run_board.py bench-alice
../tools/run_board.py bench-bob
```
