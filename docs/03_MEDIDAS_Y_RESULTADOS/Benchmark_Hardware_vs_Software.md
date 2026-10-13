# Benchmark: Aceleradores FPGA frente a Software en CPU

> **Programas**: `benchmark/cvqkd_cpu_benchmark.c` (Alice: reconciliación completa) y `benchmark/cvqkd_bob_cpu_benchmark.c` (Bob: cadena completa), en C con `-O3`  
> **CPU**: ARM Cortex-A9 del Zynq-7020 (PYNQ-Z2) a 650 MHz, *baremetal*, temporizador global del SCU; Intel Core i7-8665U del PC (portátil, 1,9 GHz nominales y hasta 4,8 GHz en turbo, Linux, `clock_gettime`)  
> **FPGA**: Alice en la Nexys Video a 25 MHz (contador de ciclos del acelerador); Bob en la PL de la PYNQ-Z2 a 71,4 MHz (DMA incluido)

> **Revisión (13/10/2026)**: el programa de Alice hace ahora el mismo trabajo que el acelerador sobre la misma trama (antes, LDPC solo con otra trama), y la latencia de Bob se da desglosada. Las cifras de abajo son las medidas actuales.

---

## 1. Alice: reconciliación completa

El programa hace en C el mismo trabajo que el acelerador y sobre la misma trama que la FPGA tiene en sus BRAM (`benchmark/export_benchmark_data.py` la toma de `cvqkd_matlab/data`): MDR 8D, LDPC y extracción de la clave. El decodificador reproduce la aritmética de la RTL (mensajes de 8 bits, LLR de 10 bits, 0,75 × mínimo como `raw - raw/4`) y su criterio de parada (síndrome correcto y ningún bit duro cambia), así que converge en las mismas 13 iteraciones que la placa y da la clave de Bob en 50/50 tramas.

| Plataforma | MDR 8D | LDPC (13 it.) | Clave | Trama completa | Por iteración | Aceleración de la FPGA (trama / iteración) |
|---|---|---|---|---|---|---|
| ARM Cortex-A9, 650 MHz (placa, 13/10) | 3,76 ms | 156,80 ms | 0,27 ms | 160,82 ms | 12,06 ms | **96×** / **276×** |
| Intel Core i7-8665U (13/10, enchufado, media de 3 pasadas) | 0,20 ms | 11,02 ms | 0,03 ms | 11,23 ms | 0,85 ms | **6,7×** / **19×** |
| FPGA Artix-7, 25 MHz (placa) | 41.783 ciclos | | | 1,67 ms | 43,76 µs | — |

- La aceleración por trama es menor que por iteración porque la FPGA tiene 1,10 ms de coste fijo (carga del síndrome, MDR y clave) que en CPU es casi despreciable.
- Por ciclo de reloj, la FPGA hace en cada iteración 276 × 650/25 ≈ 7.200 veces el trabajo del ARM.
- El i7 depende del estado del portátil: con batería y regulador en ahorro, el mismo programa da unos 1,5 ms por iteración.
- La versión anterior del programa (LDPC solo, trama del 29/09, 7 iteraciones) daba 15,95 ms por iteración en el ARM (364×) y 0,72 ms en el i7 (16,4×). El ARM es ahora más rápido porque el índice de rotación ya no usa una división (el Cortex-A9 no divide por hardware); el i7 es algo más lento por las saturaciones y el criterio de parada de la RTL.

---

## 2. Bob: cadena completa

El programa ejecuta la compensación de fase, la criba y estimación, el MDR 8D, el síndrome y la evaluación de seguridad sobre la trama de MATLAB (vectores heterodinos actuales). La FPGA hace lo mismo salvo la seguridad, que sigue en el ARM.

| Etapa | ARM Cortex-A9 (04/10) | Intel Core i7-8665U (13/10) |
|---|---|---|
| Compensación de fase | 15,19 ms (69,4 %) | 0,50 ms (41 %) |
| Criba y estimación | 1,04 ms (4,7 %) | 0,12 ms (10 %) |
| MDR 8D (3.264 bloques) | 5,51 ms (25,2 %) | 0,59 ms (48 %) |
| Síndrome LDPC | 0,11 ms (0,5 %) | 5 µs (0,4 %) |
| Seguridad (Holevo) | 8 µs | ~1 µs |
| **Total por trama** | **21,87 ms** | **1,23 ms** |
| FPGA (placa, con DMA) | 1,91 ms: **11,5×** | 1,91 ms: 0,64× |

Medias de 50 tramas. En el ARM, la compensación de fase y el MDR suman el 95 % del tiempo: son las etapas que hace la PL. Frente al ARM, la FPGA es 11,5× más rápida (unas 104 veces más trabajo por ciclo, con la PL a 71,4 MHz frente a 650 MHz). El i7 es más rápido que la PL (1,23 ms frente a 1,91 ms): la PL procesa una muestra por ciclo a 71,4 MHz y el tiempo medido incluye el vaciado de caché y los DMA. El acelerador libera al ARM, que solo evalúa la seguridad (8 µs por bloque).

Desglose de los 1,91 ms de la FPGA (medido en placa el 13/10, media de 3000 tramas): 0,975 ms de preparación en el ARM (reset, carga de la clave por AXI-Lite y vaciado de caché), 0,774 ms de acelerador (DMA y cálculo en la PL) y 0,17 ms de lectura de resultados. Contando solo la parte de acelerador, que es lo que cronometra el software (datos en memoria → resultados en memoria), la FPGA es 28× más rápida que el ARM y 1,6× más rápida que el i7. Método en `2026-10-13_Medida_de_Tiempos.md`.

La cifra del 29/09 (17,97 ms) se midió con los vectores anteriores al modelo heterodino; la compensación de fase es la etapa que ha crecido (11,27 → 15,19 ms). El benchmark usaba además $V_A = 4$ SNU (40.000 cuentas) en lugar de 5: no cambia los tiempos, pero su comprobación de la estimación no coincidía con el hardware. Corregido el 04/10.

---

## 3. Energía (estimación)

No se ha medido la potencia. Estimación de `report_power` de Vivado tras el rutado (sin vectores de actividad): diseño de Alice 1,26 W; Zynq-7020 de Bob 1,74 W, de los que 1,26 W son del PS7. Para el i7 se usa su TDP, 15 W.

| | Potencia | Alice: energía por trama | Bob: energía por trama |
|---|---|---|---|
| ARM Cortex-A9 (PS7) | 1,26 W | 203 mJ | 27,6 mJ |
| Intel Core i7-8665U | 15 W (TDP) | 168 mJ | 18,5 mJ |
| FPGA de Alice | 1,26 W | 2,1 mJ | — |
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
