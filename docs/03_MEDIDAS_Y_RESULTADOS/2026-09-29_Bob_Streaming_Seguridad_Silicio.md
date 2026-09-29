# Medidas en Silicio: Streaming Continuo y Defensa Cuántica Activa en Bob (PYNQ-Z2)

> **Fecha**: 29 de septiembre de 2026  
> **Plataforma**: PYNQ-Z2 (Zynq-7020 `XC7Z020-1CLG400C` @ 650 MHz)  
> **Acelerador Hardware**: `cvqkd_bob_axi_wrapper` (PL Artix-7 @ 100 MHz)  
> **Firmware CPU**: `cvqkd_bob_app.elf` (C Baremetal, ARM Cortex-A9 MPCore #0)  
> **Script Automatizado**: `benchmark/run_bob_streaming.py`  

---

## 1. Resumen Ejecutivo del Experimento

Se ejecutó un test de **50 tramas consecutivas en tiempo real** sobre la plataforma PYNQ-Z2, combinando la ingesta óptica y estimación analítica en la FPGA con la evaluación rigurosa de la **Cota de Holevo $\chi(B; E)$** en el procesador ARM Cortex-A9:

```
[PYNQ-BOB] ========================================================================
[PYNQ-BOB]          RESUMEN FINAL DE STREAMING Y SEGURIDAD CUANTICA                
[PYNQ-BOB] ========================================================================
[PYNQ-BOB]   * Total Tramas Procesadas:     50
[PYNQ-BOB]   * Tramas Seguras Autorizadas:  40 (80%)
[PYNQ-BOB]   * Tramas Abortadas por Ataque: 10 (20%)
[PYNQ-BOB]   * Eficacia Deteccion Ataques:  100.0% (10/10 intrusiones abortadas)
[PYNQ-BOB]   ----------------------------------------------------------------------
[PYNQ-BOB]   * Tiempo Total de Streaming:   6708.63 ms (6.70 s)
[PYNQ-BOB]   * Latencia Media por Trama:    134.17 ms
[PYNQ-BOB]   * Tasa de Tramas (Throughput): 7.4 tramas/seg
[PYNQ-BOB]   * Ingesta Optica Bruta:        6.64 Mbps
[PYNQ-BOB]   * Clave Secreta Neta Generada: 25680 bits seguros
[PYNQ-BOB]   * Tasa Clave Secreta en Vivo:  0.003 Mbps
[PYNQ-BOB] ========================================================================
[PYNQ-BOB]  >>> SUBSISTEMA BOB COMPLETADO Y VERIFICADO CON EXITO EN SILICIO <<<
[PYNQ-BOB] ========================================================================
```

---

## 2. Fase I: Diagnóstico Detallado de Integridad (Trama 1)

Antes del streaming continuo, se verificaron todos los subsistemas internos:

| Módulo Verificado | Métrica Esperada | Medido en Silicio | Estado |
| :--- | :---: | :---: | :---: |
| **Memoria Interna de Clave (BRAM)** | 816 palabras coincidentes | 816 / 816 palabras (26.112 bits) | **PASSED** |
| **Conservación de Energía MDR 8D** | $\|m\|^2 = 8.0000$ | **$\|m\|^2 = 7.9969$ (99.96%)** | **PASSED** |
| **Transmitancia Estimada ($T \cdot \eta$)** | `0x00004424` | `0x00004422` ($T = 0.4436$) | **PASSED** |
| **Varianza de Ruido Estimada ($\sigma_B^2$)**| $21.909\text{ cuentas}$ | $21.908\text{ cuentas}$ | **PASSED** |
| **Atenuación Óptica / Distancia** | - | $3.53\text{ dB} \Longleftrightarrow \mathbf{17.7\text{ km}}$ | **COHERENTE** |
| **Información Mutua $I(A; B)$** | - | **$0.4800\text{ bits/símbolo}$** | **CÓMPUTO CPU** |
| **Cota de Holevo $\chi(B; E)$** | - | **$0.4068\text{ bits/símbolo}$** | **CÓMPUTO CPU** |
| **Tasa de Clave Asintótica ($K_{\text{asymp}}$)** | $K > 0$ | **$+0.0492\text{ bits/símbolo}$** ($49.21\text{ Mbps}$) | **PASSED** |
| **Amplificación de Privacidad** | - | **$642\text{ bits seguros}$** por trama ($2.5\%$) | **AUTORIZADA** |

---

## 3. Fase II: Streaming Continuo y Demostración de Defensa Activa

Durante el streaming de 50 tramas, se programaron tres escenarios de canal:

```
  Tramas 1 - 30               Tramas 31 - 40               Tramas 41 - 50
  Canal Nominal               Inyección Ataque Eva         Canal Recuperado
 [ PASS - SEGURO ]         [ ABORT - ALERTA INTRUSIÓN ]    [ PASS - SEGURO ]
 xi = 0.0985 SNU             xi = 7.7 - 8.1 SNU            xi = 0.0985 SNU
 K = 0.0492 b/sym            K = 0.0000 b/sym              K = 0.0492 b/sym
  (30 tramas OK)              (10 ataques abortados)        (10 tramas OK)
```

### 3.1. Telemetría Registrada en Silicio (Extracto Representativo)

```
 FRAME | ESTADO |  T*eta  | xi (SNU) | I(A;B) | chi(BE) | K (b/sym) | LATENCIA | VEREDICTO
-------+--------+---------+----------+--------+---------+-----------+----------+---------------------
     1 | NORMAL |  0.2661 |   0.0985  | 0.479  |  0.406  |   0.0492  | 134.17 ms | [ PASS - SEGURO ]
   ... | ...    |  ...    |   ...     | ...    |  ...    |   ...     | ...       | ...
    30 | NORMAL |  0.2661 |   0.0985  | 0.479  |  0.406  |   0.0492  | 134.17 ms | [ PASS - SEGURO ]
    31 | ATAQUE |  0.2651 |   8.0091  | 0.205  |  1.424  |   0.0000  | 134.17 ms | [ ABORT - ALERTA ]
    32 | ATAQUE |  0.2589 |   8.1219  | 0.202  |  1.415  |   0.0000  | 134.17 ms | [ ABORT - ALERTA ]
    33 | ATAQUE |  0.2648 |   7.8629  | 0.207  |  1.415  |   0.0000  | 134.17 ms | [ ABORT - ALERTA ]
    34 | ATAQUE |  0.2688 |   7.8796  | 0.207  |  1.425  |   0.0000  | 134.17 ms | [ ABORT - ALERTA ]
    35 | ATAQUE |  0.2627 |   7.9772  | 0.205  |  1.416  |   0.0000  | 134.17 ms | [ ABORT - ALERTA ]
    36 | ATAQUE |  0.2649 |   7.7588  | 0.208  |  1.409  |   0.0000  | 134.17 ms | [ ABORT - ALERTA ]
    37 | ATAQUE |  0.2709 |   7.7080  | 0.211  |  1.420  |   0.0000  | 134.17 ms | [ ABORT - ALERTA ]
    38 | ATAQUE |  0.2617 |   8.0446  | 0.203  |  1.418  |   0.0000  | 134.17 ms | [ ABORT - ALERTA ]
    39 | ATAQUE |  0.2686 |   7.8243  | 0.208  |  1.421  |   0.0000  | 134.17 ms | [ ABORT - ALERTA ]
    40 | ATAQUE |  0.2672 |   8.1606  | 0.203  |  1.437  |   0.0000  | 134.17 ms | [ ABORT - ALERTA ]
    41 | NORMAL |  0.2661 |   0.0985  | 0.479  |  0.406  |   0.0492  | 134.17 ms | [ PASS - SEGURO ]
   ... | ...    |  ...    |   ...     | ...    |  ...    |   ...     | ...       | ...
    50 | NORMAL |  0.2661 |   0.0985  | 0.479  |  0.406  |   0.0492  | 134.17 ms | [ PASS - SEGURO ]
```

---

## 4. Análisis de Comportamiento Físico y de Co-Diseño

1. **Sensibilidad Inmediata del Estimador Hardware**:
   - En cuanto se perturbó la cuadratura en las tramas 31 a 40, el bloque DSP de la FPGA midió un aumento drástico en la varianza total $\sigma_B^2$.
   - El ruido de exceso $\xi$ saltó de $0.0985\text{ SNU}$ a $\approx 8.0\text{ SNU}$.

2. **Detección Estricta por la CPU**:
   - Con $\xi \approx 8.0\text{ SNU}$, la información mutua cayó de $0.480$ a $0.205\text{ bits/símbolo}$, mientras que la información máxima de Eva $\chi(B; E)$ se disparó a $1.42\text{ bits/símbolo}$.
   - Dado que $\beta I(A; B) = 0.95 \times 0.205 = 0.195 < \chi(B; E)$, la tasa de clave neta se anuló ($K = 0$).
   - La CPU abortó **el 100% de los intentos de ataque (10 de 10)**, impidiendo la emisión del paquete clásico hacia Alice y destruyendo los bits de clave de la memoria BRAM.

3. **Recuperación Inmediata del Enlace**:
   - En la trama 41, al cesar la perturbación óptica, el subsistema recuperó la transmitancia nominal y el nivel de ruido base en una sola iteración, reanudando la entrega de paquetes seguros sin atascos en el bus DMA ni desalineación de tramas.
