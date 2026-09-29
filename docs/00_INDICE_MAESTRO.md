# CV-QKD Hardware Accelerator — Cuaderno de Ingeniería & Documentación Maestra

> **Proyecto**: Aceleración Hardware en FPGA para Distribución Cuántica de Claves en Variables Continuas (CV-QKD)  
> **Autor**: Daniel Rosado (TFG)  
> **Repositorio**: `github.com/DaniRosado/cvqkd_code`  
> **Plataformas Hardware**:
> - **Alice**: Digilent Nexys Video (Xilinx Artix-7 `XC7A200T-1SBG484C` @ 25 MHz) + Softcore MicroBlaze
> - **Bob**: PYNQ-Z2 (Xilinx Zynq-7020 `XC7Z020-1CLG400C` @ 100 MHz) + ARM Cortex-A9 Dual-Core

---

## 🚀 Resumen Ejecutivo y Estado Actual del Proyecto

A fecha **29 de septiembre de 2026**, el acelerador hardware de **Alice** se encuentra **completamente operativo y verificado en silicio real**:

| Parámetro | Valor Obtenido en Silicio | Notas Técnicas |
| :--- | :---: | :--- |
| **Tasa de Error de Clave (BER Post-FEC)** | **0.0000% (0 errores)** | 816 / 816 palabras de 32 bits coincidentes exactamente con Bob (26.112 bits) |
| **Resistencia al Streaming Continuo** | **1.000 / 1.000 tramas (100.0%)** | 0 colapsos, 0 bloqueos de bus AXI, 0 timeouts |
| **Throughput de Reconciliación Sostenido** | **21.04 Mbps** | 805 tramas/segundo procesadas back-to-back en silicio |
| **Latencia Media por Trama (Nominal)** | **1.24 ms** | Decodificación LDPC completa en 7 iteraciones |
| **Aceleración Hardware vs CPU (Speedup)** | **$\approx 492\times$ a $4.000\times$** | FPGA (1.24 ms) vs Decodificador Software en Python (611 ms) |
| **Bits de Clave Reconciliados en Prueba** | **26.112.000 bits (26.11 Mb)** | Procesados en 1.25 segundos sin pausas |
| **Telemetría de Estado en Tiempo Real** | **`REG_STATUS[15:8]`** | Reporta ciclo a ciclo el número exacto de iteraciones ejecutadas |

---

## 🗂️ Mapa de Contenidos (MOC — Obsidian Vault)

### [[01_ARQUITECTURA_HARDWARE/]]
- [[01_ARQUITECTURA_HARDWARE/Sistema_Global_CVQKD|Sistema Global CV-QKD]]: Topología del enlace cuántico Alice-Bob, sincronización por pulsos piloto y canal SMF-28.
- [[01_ARQUITECTURA_HARDWARE/Acelerador_Alice_FPGA|Acelerador de Alice en FPGA]]: Diseño RTL del subsistema de Alice (Artix-7), MDR 8D, adaptador serie-paralelo y decodificador QC-LDPC 5G.
- [[01_ARQUITECTURA_HARDWARE/Mapa_Registros_AXI_Alice|Mapa de Registros AXI-Lite de Alice]]: Tabla exhaustiva de direcciones base (`0x44A00000` / `0x00004000`), registros de control, status de 32 bits y memorias BRAM.

### [[02_FUNDAMENTOS_TEORICOS/]]
- [[02_FUNDAMENTOS_TEORICOS/Protocolo_GG02_Gaussian|Protocolo GG02 y Modulación Coherente]]: Modulación Gaussiana $V_A$, ruido cuántico de disparo (SNU), exceso de ruido $\xi$, y detección homodina.
- [[02_FUNDAMENTOS_TEORICOS/Reconciliacion_MDR_8D|Reconciliación Multidimensional (MDR 8D)]]: Álgebras de Clifford, matrices ortogonales de Hurwitz-Radon, cálculo de LLRs y factor SNR $K$.
- [[02_FUNDAMENTOS_TEORICOS/Decodificador_QC_LDPC_5G|Decodificador QC-LDPC 5G-NR]]: Base Graph 1 ($46 \times 68$), tamaño de elevación $Z=384$, algoritmo Layered Min-Sum y anulación en iteración cero.

### [[03_MEDIDAS_Y_RESULTADOS/]]
- [[03_MEDIDAS_Y_RESULTADOS/2026-09-29_Verificacion_Clave_Dorada|Verificación de la Clave Dorada (BER = 0%)]]: Prueba nominal de 816 palabras bit a bit contra Bob.
- [[03_MEDIDAS_Y_RESULTADOS/2026-09-29_Streaming_Continuo_1000|Test de Streaming Continuo (1.000 Tramas)]]: Demostración de robustez, latencia y throughput sostenido a 21.04 Mbps.
- [[03_MEDIDAS_Y_RESULTADOS/2026-09-29_Curva_Waterfall_Factor_K|Curva Waterfall Experimental (Factor K vs Iteraciones)]]: Barrido fino de SNR ($K=16 \to 8$), progresión de 7 a 52 iteraciones y región de corte.
- [[03_MEDIDAS_Y_RESULTADOS/Benchmark_Hardware_vs_Software|Benchmark Hardware vs Software]]: Cuantificación del Speedup frente a implementaciones CPU/Python.

### [[04_GUIAS_DE_OPERACION/]]
- [[04_GUIAS_DE_OPERACION/Como_Ejecutar_Tests_Silicio|Cómo Ejecutar los Tests en Silicio]]: Comandos rápidos de ejecución con `verify_alice_key.py`, resolución de puertos `/dev/ttyUSB*` y flujo JTAG XSDB.
- [[04_GUIAS_DE_OPERACION/Compilacion_MicroBlaze_CLI|Compilación de MicroBlaze Headless]]: Instrucciones de compilación y enlazado con `mb-gcc` por línea de comandos sin interfaz gráfica.

---

## ⚡ Comandos Rápidos de Operación

### 1. Lanzar banco de pruebas completo en la FPGA
```bash
cd /home/drg/TFG/cvqkd_code
sudo ./verify_alice_key.py
```

### 2. Recompilar el firmware de MicroBlaze (`main.c` $\to$ `.elf`)
```bash
/home/drg/AMD/Xilin/2025.2/gnu/microblaze/lin/bin/mb-gcc -D__MICROBLAZE__ \
  -I/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/src \
  -isystem /home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_platform/export/cvqkd_alice_platform/sw/standalone_microblaze_0/include \
  -ffunction-sections -fdata-sections -mxl-barrel-shift -mlittle-endian -mxl-soft-mul -mcpu=v11.0 -DSDT \
  -specs=/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_platform/export/cvqkd_alice_platform/sw/standalone_microblaze_0/Xilinx.spec \
  -Wall -Wextra -Os -c /home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/src/main.c \
  -o /home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/build/CMakeFiles/cvqkd_alice_application.elf.dir/main.c.obj && \
/home/drg/AMD/Xilin/2025.2/gnu/microblaze/lin/bin/mb-gcc -ffunction-sections -fdata-sections \
  -mxl-barrel-shift -mlittle-endian -mxl-soft-mul -mcpu=v11.0 -DSDT \
  -specs=/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_platform/export/cvqkd_alice_platform/sw/standalone_microblaze_0/Xilinx.spec \
  -Wl,--no-relax -Wl,--gc-sections -Wl,-T -Wl,"/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/src/lscript.ld" \
  /home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/build/CMakeFiles/cvqkd_alice_application.elf.dir/main.c.obj \
  -L"/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/src/" \
  -L"/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_platform/export/cvqkd_alice_platform/sw/standalone_microblaze_0/lib/" \
  -Wl,--start-group,-lxilstandalone,-lxiltimer,-lgloss,-lxil,-lgcc,-lc -Wl,--end-group \
  -o /home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/build/cvqkd_alice_application.elf
```

### 3. Simulación física completa del canal en Python puro
```bash
python3 cvqkd_simulator.py
```
