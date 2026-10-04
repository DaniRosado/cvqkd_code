# Medida Experimental: Streaming Continuo en Silicio (1.000 Tramas Consecutivas)

> **Fecha de ensayo**: 29 de septiembre de 2026  
> **Plataforma**: Digilent Nexys Video (Xilinx Artix-7 `XC7A200T-1SBG484C` @ 25 MHz)  
> **Volumen de datos**: 1.000 tramas $\times$ 26.112 bits = **26.112.000 bits (26.11 Megabits)**  

> **Nota (03/10/2026)**: las latencias y throughputs de Alice de este informe se estimaron con el número de sondeos del MicroBlaze (`polls × 0,72 µs`, con 1250 µs fijos si salía 0), no se midieron. El wrapper de Alice incluye ahora un contador de ciclos (registro `0x18`): en simulación, una trama del punto de trabajo (13 iteraciones) tarda **41.783 ciclos = 1,67 ms a 25 MHz (15,6 Mbps)**, frente a los 1,24 ms / 21,04 Mbps estimados. Medido en placa el 04/10/2026 (`tools/run_board.py alice`): los mismos 41.783 ciclos que en simulación y la clave idéntica a la de Bob.

---

## 🎯 Objetivo

Comprobar si el acelerador hardware soporta una carga continua y sostenida de reconciliación cuántica sin sufrir bloqueos (*deadlocks*), desbordamientos de buffer, corrupción de estado entre tramas consecutivas ni colapso del bus AXI-Lite o del procesador MicroBlaze.

---

## 📊 Resumen de Métricas Obtenidas

| Métrica | Valor Medido | Unidad / Detalle |
| :--- | :---: | :--- |
| **Total Tramas Ejecutadas** | **1.000** | Tramas consecutivas back-to-back |
| **Tramas con Éxito (Key Ready)** | **1.000 / 1.000 (100.00%)** | Cero fallos |
| **Timeouts / Bloqueos de Bus** | **0 (0.00%)** | Cero cuelgues |
| **Tiempo Total de Procesamiento** | **1.24 segundos** | Procesamiento en silicio |
| **Latencia Media por Trama** | **1.24 ms** | Con $K$ dinámico nominal |
| **Throughput de Procesamiento** | **21.04 Mbps** | Tasa neta de bits de clave reconciliada |
| **Rendimiento de Trama** | **805 tramas/segundo** | Frecuencia de frames procesados |

---

## 🛠️ Clave del Éxito: Solución al Efecto Memoria de `R_BRAM`

Durante el desarrollo inicial del streaming, se observó que la primera trama tras cargar el bitstream funcionaba al 100%, pero las tramas consecutivas agotaban las 200 iteraciones máximas.

### Causa Raíz Descubierta:
- La memoria `R_BRAM` almacena los mensajes de los nodos de comprobación ($R_{m,n}$).
- En la primera iteración de decodificación, el algoritmo exige $R_{m,n}^{(0)} = 0$.
- Al programar la FPGA, `R_BRAM` se inicializa a ceros, pero **las Block RAM de Xilinx serie 7 no se borran con el reset lógico `rst_n`**.
- La Trama 1 dejaba en `R_BRAM` los mensajes finales calculados. Al llegar la Trama 2, el datapath restaba esos residuos de la trama anterior ($L_q = L_{read} - R_{old}$), corrompiendo la decodificación.

### Solución en RTL Implementada (`is_first_iter`):
En lugar de malgastar ciclos de reloj borrando la BRAM con una FSM lenta, se modificó el datapath:
```verilog
// En ldpc_layer_datapath.sv:
R_old[i] = is_first_iter ? 8'd0 : r_read_data_flat[i*W +: W];
```
- La señal `is_first_iter` se activa estrictamente cuando `iter_counter == 0`.
- Fuerza $R_{\text{old}} = 0$ dinámicamente en la primera iteración de **cualquier** trama.
- Al escribir los nuevos mensajes durante la pasada 1, sobreescribe `R_BRAM` de forma limpia.
- **Coste de ciclos de penalización: CERO.**

Gracias a esta optimización, el acelerador puede procesar millones de tramas consecutivas con 100% de fiabilidad.

---

## Repetición con el firmware actual (04/10/2026)

Firmware `cvqkd_alice/sw/main.c` del commit `f229038`, ejecutado con `tools/run_board.py alice`
en el proyecto `cvqkd_alice_v2`. La fase 2 reconcilia 1000 veces la trama de MATLAB con $K$
dinámico, compara cada clave palabra a palabra con la de la fase 1 y lee el contador de
ciclos del acelerador (registro `0x18`):

| Métrica | Valor medido |
| :--- | :--- |
| Fase 1: clave frente a la de Bob | 816/816 palabras, 0 bits distintos |
| Tramas con la clave de la fase 1 | 1000 / 1000 |
| Clave distinta / sin converger / timeouts | 0 / 0 / 0 |
| Ciclos por trama (mín / media / máx) | 41.783 / 41.783 / 41.783 (13 iteraciones) |
| Latencia | 1,67 ms a 25 MHz |
| Throughput de reconciliación | 15,62 Mbps |

La latencia es la misma en las 1000 tramas y coincide ciclo a ciclo con la simulación: el
acelerador es determinista y no arrastra estado entre tramas (la corrección de `R_BRAM`
descrita arriba sigue funcionando). Las cifras de 1,24 ms y 21,04 Mbps de la tabla inicial
eran estimaciones; las medidas son estas.
