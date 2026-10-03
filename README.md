# Acelerador hardware para el post-procesado de CV-QKD

Trabajo Fin de Grado: aceleración en FPGA del post-procesado de un sistema de
distribución cuántica de claves de variable continua (protocolo GG02 con modulación
gaussiana, detección heterodina y reconciliación inversa).

| Extremo | Placa | Qué hace el hardware | Qué hace el procesador |
| :--- | :--- | :--- | :--- |
| **Bob** | PYNQ-Z2 (Zynq-7020) | Recuperación de fase con pilotos, estimación de parámetros, reconciliación multidimensional (MDR 8D) y síndrome LDPC | ARM Cortex-A9: DMA, evaluación de seguridad (cota de Holevo, tamaño finito) y decisión PASS/ABORT |
| **Alice** | Nexys Video (Artix-7 200T) | MDR 8D (LLR) y decodificador LDPC 5G-NR BG1 (Z = 384, Min-Sum por capas) | MicroBlaze: control y lectura de la clave reconciliada |

## Estructura del repositorio

```
cvqkd_alice/      Alice: RTL del decodificador LDPC y del wrapper AXI, testbenches,
                  restricciones de la Nexys Video, script del proyecto Vivado y firmware
cvqkd_bob/        Bob: RTL (DSP, estimador, síndrome, wrapper AXI), cores de Xilinx (ip/),
                  testbenches, script del proyecto Vivado y firmware (sw/)
cvqkd_mdr/        Reconciliación multidimensional 8D (compartida por Alice y Bob)
cvqkd_matlab/     Modelo de referencia en MATLAB y vectores de test (data/)
benchmark/        Las mismas cadenas en software (PC y ARM) para comparar con la FPGA
tools/            run_board.py (ejecución en placa) y simulador del canal en Python
docs/             Documentación técnica (arquitectura, fundamentos y medidas)
run_tests.sh      Regresión de simulación
```

## Requisitos

- Vivado y Vitis 2025.2 (las versiones de los cores de Xilinx están fijadas a esta release).
- MATLAB (solo para regenerar los vectores de test).
- Python 3 y gcc (scripts y benchmarks en el PC).

## Simulación

```bash
./run_tests.sh            # 20 tests: unitarios, subsistemas y wrappers AXI completos
./run_tests.sh --list
./run_tests.sh tb_cvqkd_bob_axi_wrapper
```

Necesita `xvlog`/`xelab`/`xsim` en el `PATH` o la variable `XILINX_VIVADO`. Los
testbenches leen los vectores de `cvqkd_matlab/data` por nombre y escriben
`RESULTADO: PASS` o `RESULTADO: FAIL`; los logs quedan en `build/sim/`. La
regresión completa tarda unos 20 minutos (el wrapper de Bob con los netlists de los
CORDIC es el más lento).

## Proyectos de Vivado

Los dos proyectos se crean desde el repositorio, sin IP empaquetadas: los wrappers se
instancian como referencia a módulo, así que un cambio en la RTL solo requiere
regenerar el bitstream.

```bash
vivado -mode batch -source cvqkd_bob/scripts/create_bob_project.tcl -tclargs ~/VivadoProyects/cvqkd_bob
vivado -mode batch -source cvqkd_alice/scripts/create_alice_project.tcl -tclargs ~/VivadoProyects/cvqkd_alice
```

Después: *Generate Bitstream* y *File > Export > Export Hardware* (incluyendo el
bitstream) para obtener el `.xsa`.

| | Bob | Alice |
| :--- | :--- | :--- |
| Dispositivo | `xc7z020clg400-1` | `xc7a200tsbg484-1` |
| Reloj del acelerador | 71,4 MHz (FCLK0 del PS) | 25 MHz (`clk_wiz`) |
| Procesador | Cortex-A9 a 650 MHz | MicroBlaze, 16 KB de memoria local |

## Firmware (Vitis)

1. Crea una plataforma a partir del `.xsa` (*standalone*) y una aplicación vacía.
2. Copia en `src/` los ficheros de `cvqkd_bob/sw/` o `cvqkd_alice/sw/` (`main.c`,
   `lscript.ld`, `UserConfig.cmake`; en Bob también `cvqkd_security.*` y `matlab_vectors.h`).
3. Compila. `UserConfig.cmake` ya enlaza `libm`, que necesita el módulo de seguridad.

## Ejecución en placa

```bash
tools/run_board.py bob           # PYNQ-Z2: verificación con MATLAB (fase I) y streaming por bloques (fase II)
tools/run_board.py alice         # Nexys Video: compara la clave reconciliada con la de Bob, bit a bit
tools/run_board.py bench-bob     # Cadena de Bob en software en el ARM (benchmark/)
```

Programa la FPGA y carga el ELF con `xsdb` (variable `XILINX_VITIS` o `xsdb` en el
`PATH`), detecta la UART y muestra la salida. Las rutas del workspace de Vitis se
pueden cambiar con `VITIS_WS` o con las opciones `--bit` y `--elf`.

## Vectores de test

| Script | Genera |
| :--- | :--- |
| `cvqkd_matlab/scripts/tb_generador_master.m` | Canal, DSP, estimación, MDR y LDPC de referencia: `cvqkd_matlab/data/*` y `cvqkd_alice/rtl/bg1_rom_pkg.sv` |
| `cvqkd_matlab/scripts/evaluador_newton_raphson.m` | Estudio de la raíz inversa del MDR y `cvqkd_mdr/rtl/mdr_rom_pkg.sv` |
| `cvqkd_bob/sw/export_matlab_to_c.py` | `matlab_vectors.h` para el firmware de Bob |

## Resultados principales

| Medida | Valor |
| :--- | :--- |
| Bob, latencia por trama en placa | 1,94 ms (DMA + acelerador, 514 tramas/s, 459 Mbps de ingesta) |
| Bob, tasa de clave en vivo | 99,7 kbps (bloques de 1000 tramas, 10 km, ξ = 0,01 SNU) |
| Bob, ataque de interceptación y reenvío | Bloque abortado con solo un 1 % de tramas atacadas |
| Alice, latencia por trama (simulación) | 41.783 ciclos: 1,67 ms a 25 MHz (13 iteraciones LDPC) |
| Verificación | Estimación y síndrome de Bob idénticos a MATLAB; clave de Alice idéntica a la de Bob |

El detalle está en [docs/03_MEDIDAS_Y_RESULTADOS](docs/03_MEDIDAS_Y_RESULTADOS).

## Limitaciones y trabajo futuro

- **Aleatoriedad**: los bits de clave de Bob y la modulación de Alice salen de los
  vectores de MATLAB. Un sistema real necesita un generador de números aleatorios
  verdadero (TRNG); queda fuera del alcance de este trabajo.
- **Canal clásico**: falta la autenticación de los mensajes entre Alice y Bob y el hash
  de verificación de la clave ($\epsilon_{cor}$).
- **Canal sintético**: la fase II del firmware de Bob genera las tramas en el ARM sin
  ruido de fase; la recuperación de fase se prueba con la trama de MATLAB.
- **Alice** recibe la trama de prueba precargada en el bitstream: la Nexys Video no
  tiene memoria externa conectada en este diseño.
