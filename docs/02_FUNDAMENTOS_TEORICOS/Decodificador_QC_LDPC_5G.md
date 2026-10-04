# Fundamentos Teóricos: Decodificador QC-LDPC 5G-NR y Algoritmo Min-Sum en Capas

> **Módulos RTL asociados**: `ldpc_decoder_top.sv`, `ldpc_controller_fsm.sv`, `ldpc_layer_datapath.sv`, `vnu_node.sv`, `cnu_serial_node.sv`, `barrel_shifter.sv`, `syndrome_checker.sv`, `L_RAM.sv`, `R_BRAM.sv`  
> **Estándar**: 3GPP TS 38.212 (5G-NR Quasi-Cyclic Low-Density Parity-Check)  
> **Topología**: Base Graph 1 ($46 \times 68$), Factor de Elevación $Z = 384$  

---

## 🏗️ Parámetros de la Matriz de Paridad QC-LDPC

La matriz de paridad $H$ se define mediante la expansión Quasi-Cíclica de la matriz base (*Base Graph 1*):

$$H \in \{0, 1\}^{M \times N}, \quad M = 46 \times 384 = 17.664\text{ filas}, \quad N = 68 \times 384 = \mathbf{26.112\text{ columnas (bits)}}$$

Cada entrada $(r, c)$ en el Base Graph 1 contiene un valor de desplazamiento cíclico $P_{r,c}$:
- Si $P_{r,c} = -1$: Submatriz nula de $384 \times 384$ ceros.
- Si $P_{r,c} \ge 0$: Matriz identidad de $384 \times 384$ desplazada circularmente a la derecha $P_{r,c}$ posiciones.

---

## ⚡ Algoritmo de Decodificación Min-Sum en Capas (Layered Min-Sum)

A diferencia del decodificador estándar en dos fases (*Two-Phase Scheduling* o Flooding), la decodificación en capas actualiza los nodos de variable inmediatamente después de procesar cada fila de la matriz base. Esto duplica la velocidad de convergencia efectiva, permitiendo decodificar en **7 a 13 iteraciones** lo que requeriría 15 a 30 en Flooding.

### 1. Actualización del Nodo de Variable (VNU — Fase 1: Lectura y Resta):
Para cada arista $(r, c)$ de la fila activa, se resta la información extrínseca anterior procedente del nodo de comprobación:

$$L_q^{(i)} = L_{\text{read}}^{(i)} - R_{\text{old}}^{(i-1)}$$

> **Regla de Oro en Iteración 0**:
> En la primera iteración ($i = 0$), no existe información previa de paridad, por lo que:
> $$R_{\text{old}}^{(0)} = 0 \implies L_q^{(0)} = L_{\text{read}}^{(0)}$$

### 2. Rotación Cíclica (Barrel Shifter):
El vector $L_q$ de 384 LLRs se desplaza circularmente $P_{r,c}$ posiciones mediante el módulo `barrel_shifter.sv` para alinear las variables con las restricciones de la fila activa.

### 3. Actualización del Nodo de Comprobación (CNU — Cálculo de Mínimos):
Para todos los nodos de variable conectados a la fila de comprobación, se calculan los dos valores absolutos mínimos y el producto de signos:

$$min_1 = \min_{c'} |L_{q, c'}|, \quad min_2 = \min_{c'' \ne \text{argmin}} |L_{q, c''}|, \quad S_{\text{total}} = \prod_{c'} \text{sgn}(L_{q, c'})$$

El nuevo mensaje de comprobación $R_{\text{new}}$ para la variable $c$ viene dado por (*Min-Sum normalizado*, $\alpha = 0.75$):

$$R_{\text{new}} = \alpha \cdot (S_{\text{total}} \cdot \text{sgn}(L_{q, c})) \times \begin{cases} min_2 & \text{si } |L_{q, c}| = min_1 \\ min_1 & \text{si } |L_{q, c}| > min_1 \end{cases}$$

En hardware, el escalado $\alpha = 0.75$ se hace como $x - (x \gg 2)$ una sola vez, tras elegir $min_1$ o $min_2$.

### 4. Actualización del Nodo de Variable (VNU — Fase 2: Suma y Escritura):
Se desrotan los mensajes $R_{\text{new}}$ y se suman a la información previa para obtener el LLR posterior actualizado:

$$L_{\text{write}}^{(i)} = L_q^{(i)} + R_{\text{new}}^{(i)}$$

El resultado $L_{\text{write}}$ se guarda de nuevo en `L_BRAM`, mientras que $R_{\text{new}}$ se guarda en `R_BRAM` para la siguiente iteración.

---

## 🎯 Verificación del Síndrome y Parada Temprana (Early Stopping)

Al finalizar cada iteración completa de las 46 filas, el módulo `syndrome_checker.sv` evalúa bit a bit si las decisiones duras $\hat{b}_n = (L_n < 0)$ satisfacen el síndrome de Bob:

$$\mathbf{s}_{\text{calc}} = H \cdot \hat{\mathbf{b}} \pmod 2 \stackrel{?}{=} \mathbf{s}_{\text{Bob}}$$

En la práctica, la comprobación de cada fila se hace al vuelo, justo después de actualizarla. Como las capas posteriores pueden volver a cambiar el signo de variables compartidas, la convergencia solo se declara si **además ningún bit duro cambió durante la iteración** (`hd_changed`): en ese caso las comprobaciones hechas sobre la marcha equivalen al síndrome de la decisión final.

- Si se cumple: la señal `is_converged` pasa a `1`, la decodificación se **detiene**, se activa `ldpc_success = 1` y la clave se copia a `key_bram`.
- Si no: la FSM arranca una nueva iteración, hasta un máximo de `MAX_ITER = 200`.

---

## 🔢 Formatos Numéricos en Hardware

| Magnitud | Formato | Motivo |
| :--- | :--- | :--- |
| Mensajes $R$ y $L_q$ hacia la CNU | Signo-magnitud de $W = 8$ bits ($\pm 127$) | Anchura de los 384 nodos CNU y de las memorias `R_BRAM` |
| LLR a posteriori $L$ en `L_BRAM` | Signo-magnitud de $WL = 10$ bits ($\pm 511$) | Con 8 bits el posterior se saturaba y el decodificador divergía tras unas pocas iteraciones |
| $L_q$ exacto en el camino de escritura | Complemento a 2 de $WL+1$ bits | $L_{\text{write}} = L_q + R_{\text{new}}$ sin perder la confianza acumulada |

Con la trama de MATLAB del punto de trabajo (10 km), el decodificador converge en 13 iteraciones.
Cada iteración cuesta 1.094 ciclos: la latencia de Alice es $27\,561 + 1\,094 \cdot it$ ciclos
(1,67 ms con 13 iteraciones a 25 MHz y 9,85 ms si agota las 200). La tasa de éxito frente a la
SNR está en [la curva waterfall](../03_MEDIDAS_Y_RESULTADOS/2026-10-04_Waterfall_LDPC_Simulacion.md).
