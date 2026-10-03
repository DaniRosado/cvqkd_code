# Arquitectura y Co-Diseño Hardware/Software de Bob (PYNQ-Z2)

> **Plataforma**: PYNQ-Z2 (Xilinx Zynq `XC7Z020-1CLG400C`)  
> **Lógica programable**: 71,4 MHz (FCLK0 del PS) · **Procesador**: ARM Cortex-A9 a 650 MHz  
> **Proyecto**: `cvqkd_bob/scripts/create_bob_project.tcl` · **Firmware**: `cvqkd_bob/sw/`  
> **Última actualización**: 3 de octubre de 2026

---

## 1. Visión general

Bob es el extremo que mide: recibe las dos cuadraturas del receptor heterodino, corrige
la fase con los pilotos, estima el canal con las muestras que Alice revela y genera la
información de reconciliación (mensajes MDR y síndrome LDPC). La CPU orquesta los DMA
y decide si el bloque es seguro.

```
                PS: ARM Cortex-A9 (650 MHz)
   DMA, carga de la clave, evaluación de seguridad (Holevo + tamaño finito), PASS/ABORT
        |  AXI4-Lite (GP0)                         |  AXI HP0 (DDR)
        v                                          v
 +-----------------------------------------------------------------------------+
 |  PL (71,4 MHz)                    cvqkd_bob_axi_wrapper                      |
 |                                                                             |
 |  DMA0 MM2S ADC {Q,P} --> DSP: demux pilotos -> CORDIC vect -> interpolador  |
 |                          -> FIFO -> CORDIC rot  --> router (FIFO de trama)  |
 |  DMA2 MM2S máscara ----> deserializador 32:1 ----^        |          |      |
 |                                              sacrificio |          | clave|
 |  DMA1 MM2S Alice ------> estimador: 2 x mac_moments -> LLR_math_unit       |
 |                          (T*eta/2, sigma^2 en registros)          |         |
 |  clave (AXI-Lite) -----> acumulador 8D -> MDR 8D ------------> DMA0 S2MM    |
 |                                       -> síndrome (ping-pong) -> DMA1 S2MM  |
 +-----------------------------------------------------------------------------+
```

---

## 2. Partición hardware / software

| Función | Dónde | Implementación | Motivo |
| :--- | :---: | :--- | :--- |
| Recuperación de fase | PL | 2 CORDIC (IP) + interpolador lineal entre pilotos (1 cada 16 símbolos) | Una muestra por ciclo, sin intervención de la CPU |
| Criba de sacrificio | PL | FIFO de trama (32.768 × 32 bits) + máscara | Reparte la trama entre estimación y clave |
| Estimación de $t$ y $\sigma^2$ | PL | Acumuladores de momentos (DSP48) + divisor y raíz (IP) | Las sumas se hacen al ritmo de llegada de las muestras |
| MDR 8D | PL | Norma, raíz inversa por ROM, normalización y matriz ortogonal 8×8 | 3.264 mensajes por trama, uno cada 4 muestras |
| Síndrome LDPC | PL | Ping-pong de clave + acumulador de 384 bits, una arista por ciclo | 316 aristas del BG1: unos 320 ciclos por síndrome |
| DMA y control | PS | Transferencias simples, sondeo | Flexibilidad |
| Seguridad | PS | C en coma flotante (`cvqkd_security.c`) | Funciones trascendentes y autovalores simplécticos, una vez por bloque |

---

## 3. Flujo de una trama (firmware)

1. *Soft reset*, calibración de $V_A$ y carga de las 816 palabras de clave por AXI-Lite
   (el hardware usa cada byte una sola vez y bloquea la reconciliación sin clave nueva).
2. Se arman las recepciones: mensajes MDR (DMA0 S2MM, una transferencia de 104.448 B con
   TLAST en el último) y síndrome (DMA1 S2MM).
3. DMA0 envía la trama del ADC (111.428 B en una transferencia): queda entera en la
   FIFO del router.
4. DMA2 envía la máscara y DMA1 las muestras de Alice: el router reparte las muestras
   entre el estimador y la reconciliación.
5. Se espera a los DMA de salida y a `done_est`; si el hardware marca `data_loss` la
   trama se descarta.

Los DMA0 y DMA1 tienen el registro de longitud de 17 bits (hasta 128 KB por transferencia).

---

## 4. Interfaces

| DMA | Dirección | Canal | Contenido | Ancho del stream |
| :--- | :---: | :---: | :--- | :---: |
| `axi_dma_0` | `0x40400000` | MM2S | Muestras del ADC {Q, P} (27.857 × 32 bits) | 32 bits |
| `axi_dma_0` | `0x40400000` | S2MM | Mensajes MDR (3.264 × 256 bits) | 256 bits |
| `axi_dma_1` | `0x40410000` | MM2S | Muestras de sacrificio de Alice (13.056 × 32 bits) | 32 bits |
| `axi_dma_1` | `0x40410000` | S2MM | Síndrome (46 filas de 384 bits en palabras de 512) | 512 bits |
| `axi_dma_2` | `0x40420000` | MM2S | Máscara de sacrificio (816 × 32 bits) | 32 bits |

Registros y memoria de clave: [Mapa de registros de Bob](Mapa_Registros_AXI_Bob.md).

---

## 5. Medida del tiempo

El firmware mide con el temporizador global del Cortex-A9 (`0xF8F00200`, 325 MHz,
lectura atómica de 64 bits). La latencia por trama que se publica es la del acelerador
(vaciado de caché, DMA y espera); quedan fuera la generación sintética de tramas y la UART.

---

## 6. Recursos (Zynq-7020, implementación del 03/10/2026)

Diseño completo generado con `create_bob_project.tcl`, timing cumplido a 70 MHz (WNS +0,861 ns):

| Recurso | Usado | Disponible | % |
| :--- | ---: | ---: | ---: |
| LUT | 27.138 | 53.200 | 51 % |
| Flip-flops | 30.095 | 106.400 | 28 % |
| BRAM36 | 73,5 | 140 | 53 % |
| DSP48 | 52 | 220 | 24 % |

Reparto del acelerador (LUT / FF / BRAM36 / DSP):

| Bloque | LUT | FF | BRAM36 | DSP |
| :--- | ---: | ---: | ---: | ---: |
| DSP (CORDIC + interpolador) | 2.645 | 2.632 | 0,5 | 4 |
| Router (FIFO de trama) | 68 | 169 | 32 | 0 |
| Estimador (momentos + unidad matemática) | 3.323 | 5.059 | 2 | 32 |
| MDR 8D | 3.178 | 1.893 | 0 | 16 |
| Síndrome (ping-pong + acumulador) | 2.368 | 836 | 11,5 | 0 |

Frente a la versión anterior del 22/09 (37.690 LUT, 48.309 FF, 105 BRAM36, 76 DSP), el
síndrome con un solo acumulador, la FIFO de la mitad de tamaño y los productos del
estimador con su anchura real ahorran un 28 % de LUT, un 38 % de FF, un 30 % de BRAM y
un 32 % de DSP. La mayor parte de lo que queda fuera del acelerador son los DMA y la
interconexión hacia HP0, sobre todo por los streams de 256 y 512 bits de salida.
