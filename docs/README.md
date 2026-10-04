# Documentación técnica

Cómo se construye, se simula y se ejecuta el proyecto: [README principal](../README.md).

## Arquitectura hardware

- [Acelerador de Alice](01_ARQUITECTURA_HARDWARE/Acelerador_Alice_FPGA.md): MDR 8D y decodificador LDPC en la Nexys Video (MicroBlaze, 25 MHz).
- [Mapa de registros de Alice](01_ARQUITECTURA_HARDWARE/Mapa_Registros_AXI_Alice.md).
- [Co-diseño de Bob](01_ARQUITECTURA_HARDWARE/Co-Diseno_Bob_Zynq.md): reparto hardware/software en la Zynq-7020 (PL a 71,4 MHz y Cortex-A9).
- [Mapa de registros de Bob](01_ARQUITECTURA_HARDWARE/Mapa_Registros_AXI_Bob.md).

## Fundamentos

- [Seguridad: cota de Holevo y tamaño finito](02_FUNDAMENTOS_TEORICOS/Seguridad_Cuantica_Holevo_GG02.md): GG02 heterodino, reconciliación inversa y evaluación por bloques de tramas.
- [Reconciliación multidimensional 8D](02_FUNDAMENTOS_TEORICOS/Reconciliacion_MDR_8D.md).
- [Decodificador QC-LDPC 5G-NR](02_FUNDAMENTOS_TEORICOS/Decodificador_QC_LDPC_5G.md): Min-Sum por capas, formatos y criterio de parada.

## Medidas y resultados

Informes fechados de cada ensayo. Los de septiembre son anteriores a la revisión de
octubre de 2026 y llevan una nota con lo que ha cambiado.

| Fecha | Informe |
| :--- | :--- |
| 04/10/2026 | [Alice: curva waterfall con la RTL (simulación)](03_MEDIDAS_Y_RESULTADOS/2026-10-04_Waterfall_LDPC_Simulacion.md) |
| 03/10/2026 | [Bob: clave secreta con evaluación por bloques](03_MEDIDAS_Y_RESULTADOS/2026-10-03_Bob_Clave_Secreta_Bloques.md) |
| 29/09/2026 | [Alice: verificación de la clave bit a bit](03_MEDIDAS_Y_RESULTADOS/2026-09-29_Verificacion_Clave_Dorada.md) |
| 29/09/2026 | [Alice: streaming de 1000 tramas](03_MEDIDAS_Y_RESULTADOS/2026-09-29_Streaming_Continuo_1000.md) |
| 29/09/2026 | [Alice: barrido del factor K (no es un barrido de SNR)](03_MEDIDAS_Y_RESULTADOS/2026-09-29_Curva_Waterfall_Factor_K.md) |
| 29/09/2026 | [Bob: streaming de 50 tramas (modelo anterior)](03_MEDIDAS_Y_RESULTADOS/2026-09-29_Bob_Streaming_Seguridad_Silicio.md) |
| — | [Benchmark FPGA frente a CPU](03_MEDIDAS_Y_RESULTADOS/Benchmark_Hardware_vs_Software.md) |
