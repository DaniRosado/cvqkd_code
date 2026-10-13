# Cómo se Miden los Tiempos de los Aceleradores

> **Fecha**: 13 de octubre de 2026  
> **Alcance**: método de medida de la latencia de Alice (Nexys Video) y de Bob (PYNQ-Z2), y de los programas de referencia en CPU. Los resultados están en `Benchmark_Hardware_vs_Software.md`, `2026-10-03_Bob_Clave_Secreta_Bloques.md` y `2026-10-04_Waterfall_LDPC_Simulacion.md`.

---

## 1. Resumen

En el proyecto hay tres relojes distintos, y no miden lo mismo:

| Qué se mide | Reloj | Resolución | Qué incluye | Qué no incluye |
|---|---|---|---|---|
| Acelerador de Alice | Contador de ciclos dentro del propio acelerador | 40 ns (un ciclo a 25 MHz), exacto | Carga del síndrome en el LDPC, MDR, iteraciones y extracción de la clave | Cargar la trama en las BRAM; el sondeo del procesador |
| Acelerador de Bob | Temporizador global del ARM (325 MHz) alrededor de la llamada | 3,1 ns | Reset, carga de la clave, vaciado de caché, DMA de ida y vuelta, cálculo y lectura de registros | Generar la trama, la UART, la evaluación de seguridad |
| Software en el ARM | El mismo temporizador global | 3,1 ns | Solo el cálculo | Copia de datos, impresión |
| Software en el PC | `clock_gettime(CLOCK_MONOTONIC)` | 1 ns nominal | Solo el cálculo | Copia de datos, impresión |

Consecuencias:

- La latencia de Alice (1,67 ms) es tiempo de cálculo puro; la de Bob (1,91 ms) incluye además el transporte de los datos. No son comparables entre sí.
- La medida de Alice es determinista (ciclos enteros, mismo valor en todas las repeticiones). La de Bob y las de CPU tienen variación entre ejecuciones y se dan como media.
- Ninguna medida incluye el canal clásico entre Alice y Bob, que no existe en el montaje.

---

## 2. Alice: contador de ciclos en el acelerador

### 2.1. El contador

El wrapper AXI de Alice tiene un registro de 32 bits que cuenta ciclos de reloj mientras el acelerador está ocupado (`cvqkd_alice/rtl/cvqkd_alice_axi_wrapper.v`, línea 615):

```verilog
// Latencia medida en hardware: ciclos desde el arranque hasta el final (ST_DONE)
always @(posedge aclk) begin
    if (!aresetn || soft_reset)
        reg_cycles <= 0;
    else if (state == ST_IDLE && (start_mdr_pulse || auto_start_pending || start_ldpc_pulse))
        reg_cycles <= 0;
    else if (core_busy)
        reg_cycles <= reg_cycles + 1'b1;
end
```

- Se pone a cero con la orden de arranque; `core_busy` sube en ese mismo ciclo.
- `core_busy` baja en el estado `ST_DONE`, después de extraer la clave, y el contador queda congelado.
- Se lee por AXI-Lite en el registro `0x18`.

### 2.2. Lectura desde el firmware

`cvqkd_alice/sw/main.c` lanza la trama, espera a "LDPC terminado y acelerador libre" y lee el contador (línea 72):

```c
u32 cycles = Xil_In32(REG_CYCLES);
xil_printf("[ALICE] Reconciliacion completada: %d iteraciones LDPC, %d ciclos (%d us a %d MHz)\r\n",
           ST_ITERS(status), cycles, cycles / CLK_MHZ, CLK_MHZ);
```

En la fase 2 se repite la misma trama 1000 veces y se acumulan mínimo, media y máximo (línea 104). El sondeo del MicroBlaze no afecta a la medida: el contador ya está parado cuando se lee.

La conversión a tiempo usa la constante `CLK_MHZ = 25`, escrita en el firmware. Si se cambiara el reloj en Vivado, los ciclos seguirían siendo correctos, pero no los milisegundos impresos.

### 2.3. Resultado y modelo de latencia

Medido en placa (04/10/2026): 41.783 ciclos en las 1000 tramas (mínimo = media = máximo), 13 iteraciones, 1,67 ms, 15,62 Mbps (26.112 bits / 1.671 µs).

Como la cuenta es exacta, la latencia se ajusta a una recta:

**ciclos = 27.561 + 1.094 × iteraciones** (1,10 ms fijos + 43,76 µs por iteración)

- Obtenida en la simulación del wrapper (`tb_cvqkd_alice_axi_wrapper.sv` lee el mismo registro `0x18`) con tramas de 8, 13, 104 y 193 iteraciones.
- Una trama que agota las 200 iteraciones sin converger tarda 884 ciclos menos, porque no se extrae la clave: 245.477 ciclos = 9,82 ms.

`tools/alice_frames.py` comprueba el modelo en cada trama cargada por JTAG (línea 154):

```python
cyc_ok = cyc == 27561 + 1094 * iters - (0 if conv else 884)   # Sin convergencia no se extrae la clave
```

Se cumplió en las 190 tramas probadas en placa (90 del barrido de distancias y 100 a 11 km). A 11 km: 17,4 iteraciones de media, 1,87 ms de media y 3,25 ms de máximo.

### 2.4. Límites de esta medida

- No incluye la entrada de datos. En el firmware la trama está en las BRAM desde la síntesis (`$readmemh`); con `alice_frames.py` se carga por JTAG (1,7 s por trama, fuera de la medida). Los 15,62 Mbps son el caudal de cálculo, no un caudal sostenido con datos nuevos.
- La fase 2 del firmware repite una única trama: demuestra repetibilidad, no comportamiento frente a tramas distintas (eso lo cubren las tramas cargadas por JTAG).

---

## 3. Bob: temporizador del ARM alrededor del acelerador

### 3.1. El temporizador

Bob no tiene contador propio. Se usa el temporizador global del Cortex-A9 (64 bits, 325 MHz, la mitad del reloj de la CPU), en `cvqkd_bob/sw/main.c`, línea 57:

```c
#define GLOBAL_TMR_BASEADDR         0xF8F00200U
#define GTIMER_FREQ_HZ              325000000.0

static inline uint64_t read_global_timer(void) {
    uint32_t high, low;
    do {
        high = Xil_In32(GLOBAL_TMR_BASEADDR + GTIMER_COUNTER_UPPER_OFFSET);
        low = Xil_In32(GLOBAL_TMR_BASEADDR + GTIMER_COUNTER_LOWER_OFFSET);
    } while (Xil_In32(GLOBAL_TMR_BASEADDR + GTIMER_COUNTER_UPPER_OFFSET) != high);
    return (((uint64_t)high) << 32) | low;
}
```

El bucle repite la lectura si la mitad alta cambia entre medias, para no mezclar mitades de dos instantes distintos.

### 3.2. Qué se cronometra

La medida envuelve solo la llamada que procesa la trama (línea 497):

```c
// 1. Trama nueva del canal (con el ruido de Eva en las tramas atacadas)
synth_frame(&sec_params, T_channel, is_attack_frame ? ATTACK_XI : CH_XI);

// 2. Procesar la trama en el acelerador (reset, clave nueva, DMAs y espera)
uint64_t t_frame_start = read_global_timer();
bob_frame_hw_t f_hw;
if (bob_process_frame(&f_hw) != XST_SUCCESS) return XST_FAILURE;
uint64_t frame_cycles = read_global_timer() - t_frame_start;
total_stream_cycles += frame_cycles;
```

Dentro de `bob_process_frame` (línea 226), y por tanto dentro de la medida:

1. Reset del acelerador y escritura de la calibración.
2. Carga de los 26.112 bits aleatorios de Bob.
3. Vaciado e invalidación de caché de los búferes.
4. Armado de las dos recepciones por DMA (MDR y síndrome).
5. Envío de la trama completa del ADC (bloqueante), y después máscara y muestras de Alice.
6. Espera al fin de los DMA y de la estimación de parámetros.
7. Lectura de la transmitancia y la varianza.

Fuera de la medida: la síntesis de la trama (`synth_frame`), la impresión por UART y la evaluación de seguridad del bloque.

El orden ADC → máscara → muestras de Alice es un requisito del protocolo (la máscara no puede conocerse antes de terminar la transmisión cuántica) y la medida lo respeta.

### 3.3. Cálculo de las cifras

Al final se suman las 3000 tramas (línea 542):

```c
double total_stream_time_ms = ((double)total_stream_cycles / GTIMER_FREQ_HZ) * 1000.0;
double avg_lat_ms = total_stream_time_ms / (double)NUM_STREAM_FRAMES;
double fps = (double)NUM_STREAM_FRAMES / (total_stream_time_ms / 1000.0);
double optical_mbps = fps * (27857.0 * 32.0) / 1.0e6;
double net_skr_kbps = ((double)total_secure_bits / (total_stream_time_ms / 1000.0)) / 1.0e3;
```

Medido en placa: 1,91 ms por trama, 521,9 tramas/s, 465,3 Mbps de entrada. La tasa de clave segura (66,3 kbps a 11 km con ruido de fase) es bits seguros entre ese mismo tiempo acumulado.

### 3.4. Límites de esta medida

- Es tiempo de acelerador más transporte interno, no tiempo de un enlace real: las muestras no vienen de un ADC ni las de Alice de la red.
- La tasa de clave en kbps usa solo el tiempo de acelerador; no cuenta la generación de tramas ni la reconciliación en Alice.
- Al ser sondeo desde el procesador, hay variación entre tramas; se da la media.

---

## 4. Software de referencia en CPU

El mismo algoritmo en C, compilado con `-O3`, para el ARM Cortex-A9 de la PYNQ-Z2 (sin sistema operativo) y para el PC (Intel Core i7-8665U, Linux). Los datos van compilados dentro del programa (`matlab_vectors.h`, `cvqkd_benchmark_data.h`) y se copian a memoria antes de arrancar el cronómetro.

### 4.1. Relojes

En el ARM, el temporizador global de la sección 3.1. En el PC (`benchmark/cvqkd_cpu_benchmark.c`, línea 75):

```c
struct timespec ts;
clock_gettime(CLOCK_MONOTONIC, &ts);
return (double)ts.tv_sec * 1000000.0 + (double)ts.tv_nsec / 1000.0;
```

### 4.2. Alice: decodificador LDPC

El cronómetro arranca después de inicializar los LLR y se para al converger (línea 154):

```c
double t_start = get_time_us();
for (int it = 1; it <= max_iters; it++) {
    /* ... 46 capas x 384 rebanadas ... */
    if (final_errors == 0) { converged_iter = it; break; }
}
double t_end = get_time_us();
```

Se repite 50 veces y se hace la media. La comparación con la FPGA se hace **por iteración**, porque el trabajo de una iteración no depende de la trama (línea 283):

```c
const double FPGA_ITER_US = 1094.0 / 25.0;   /* 43,76 us */
double speedup = (time_us / iters) / FPGA_ITER_US;
```

| Plataforma | Por iteración | FPGA más rápida |
|---|---|---|
| FPGA de Alice (25 MHz) | 43,76 µs | — |
| ARM Cortex-A9 (29/09) | 15,95 ms | 364× |
| Intel Core i7-8665U (04/10) | 0,72 ms | 16,4× |

Avisos:

- El programa para cuando la clave coincide con la de Bob (dato que Alice no tiene); la RTL para con síndrome correcto y decisiones estables. Por eso no se comparan tramas enteras.
- Las cifras publicadas son con la trama del 29/09 (7 iteraciones). Con la trama actual (`benchmark/export_benchmark_data.py`, sin integrar todavía) el i7 converge en 11 iteraciones a 0,72–0,80 ms por iteración; la FPGA necesita 13 con esa misma trama. Falta repetir la medida en el ARM.

### 4.3. Bob: cadena completa

Una marca de tiempo entre etapa y etapa da el desglose (`benchmark/cvqkd_bob_cpu_benchmark.c`, línea 411):

```c
uint64_t t0 = read_timer_ticks();
stage1_phase_compensation(...);
uint64_t t1 = read_timer_ticks();
stage2_param_estimation(...);
uint64_t t2 = read_timer_ticks();
stage3_mdr_8d(...);
uint64_t t3 = read_timer_ticks();
stage4_ldpc_syndrome(...);
uint64_t t4 = read_timer_ticks();
stage5_security_eval(...);
uint64_t t5 = read_timer_ticks();
```

Media de 50 tramas (04/10): 21,87 ms en el ARM (FPGA 11,5× más rápida) y 1,34 ms en el i7 (más rápido que la FPGA, 1,91 ms).

Aviso: el software no mueve datos por DMA ni vacía cachés, y la medida de la FPGA sí lo incluye. La comparación favorece ligeramente a la CPU.

---

## 5. Reproducción

```bash
tools/run_board.py alice          # Alice: ciclos y latencia de 1000 tramas
tools/alice_frames.py             # Alice: tramas nuevas por JTAG, comprueba el modelo de ciclos
tools/run_board.py bob            # Bob: latencia media, tramas/s y tasa de clave
cd benchmark && make host bob_host && ./bench_host && ./bench_bob_host   # CPU del PC
make arm bob_arm                  # binarios para el ARM
../tools/run_board.py bench-alice
../tools/run_board.py bench-bob
```
