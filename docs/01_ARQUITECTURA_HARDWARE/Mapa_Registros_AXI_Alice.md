# Mapa de Registros AXI-Lite del Acelerador de Alice

> **Módulo RTL**: `cvqkd_alice_axi_wrapper.v`  
> **Interfaz de Bus**: AXI4-Lite Slave de 32 bits  
> **Espacio de Direcciones**: 8 KB (0x0000 a 0x1FFF)  
> **Dirección base**: `0x00004000` en el espacio de datos del MicroBlaze (`create_alice_project.tcl`)  

---

## 🗺️ Mapa de Memoria Completo

| Dirección Offset | Nombre de Registro | Acceso | Ancho | Descripción |
| :---: | :--- | :---: | :---: | :--- |
| **`0x00`** | **`REG_CTRL`** | R/W | 32 b | Registro de control global y disparo de operaciones |
| **`0x04`** | **`REG_STATUS`** | RO | 32 b | Registro de estado, banderas de finalización y telemetría de iteraciones |
| **`0x08`** | **`REG_K_FACTOR`** | R/W | 32 b | Factor escalar $K$ de calibración de canal (formato Q10) |
| **`0x0C`** | **`REG_K_MODE`** | R/W | 32 b | Selector de modo de $K$: `0 = Escalar manual`, `1 = Dinámico de ram_k` |
| **`0x10`** | **`REG_X_BLOCKS_RX`**| RO | 32 b | Contador de bloques recibidos por el streaming de $X$ (0 a 3.264) |
| **`0x14`** | **`REG_M_BLOCKS_RX`**| RO | 32 b | Contador de bloques recibidos por el streaming de $m$ (0 a 3.264) |
| **`0x18`** | **`REG_CYCLES`** | RO | 32 b | Ciclos de reloj de la última ejecución (del arranque al final): latencia medida en hardware |
| **`0x100` – `0x99C`**| **`syn_bram`** | R/W | 32 b | **Memoria de Síndrome de Bob**: 552 palabras de 32 bits ($17.664$ bits) |
| **`0xA00` – `0x16BC`**| **`key_bram`** | RO | 32 b | **Memoria de Clave Reconciliada**: 816 palabras de 32 bits ($26.112$ bits) |

---

## 🔍 Detalle Bit a Bit de los Registros

### 1. `REG_CTRL` (Offset `0x00`, Lectura/Escritura)

| Bits | Nombre | Valor por Defecto | Descripción |
| :---: | :--- | :---: | :--- |
| **`0`** | `soft_reset` | `0` | `1`: Reinicia la FSM del wrapper, acumuladores y módulo LDPC. |
| **`1`** | `start_mdr` | `0` | Genera un pulso de 1 ciclo para iniciar la reconciliación MDR. |
| **`2`** | `start_ldpc` | `0` | Genera un pulso de 1 ciclo para iniciar únicamente el decodificador LDPC. |
| **`3`** | `auto_run` | `0` | `1`: Conexión directa en cadena: MDR dispara automáticamente LDPC al terminar. |
| `31:4` | *Reservado* | `0` | Reservados para futuras extensiones. |

> **Comandos típicos de control**:
> - `0x01`: Reset por software.
> - `0x00`: Liberar reset.
> - `0x0A` (`0b1010`): Iniciar MDR + LDPC en cadena automática (`auto_run=1, start_mdr=1`).

---

### 2. `REG_STATUS` (Offset `0x04`, Solo Lectura)

```
 31                            16 15        8 7     5 4   3   2   1   0
+--------------------------------+-----------+-------+---+---+---+---+---+
|           Reservado (0)        | iter_cnt  | Res(0)| C | K | S | L | M |
+--------------------------------+-----------+-------+---+---+---+---+---+
```

| Bits | Nombre | Descripción |
| :---: | :--- | :--- |
| **`0`** | `mdr_done` | `1`: El módulo MDR ha finalizado de generar todos los 26.112 LLRs. |
| **`1`** | `ldpc_done` | `1`: El decodificador LDPC ha finalizado (bien por éxito o por agotar `MAX_ITER`). |
| **`2`** | `ldpc_success` | `1`: **Éxito total**: Todas las 46 ecuaciones de paridad coinciden con el síndrome ($H \cdot \hat{b} = s$). |
| **`3`** | `key_ready` | `1`: La clave reconciliada está completamente copiada en `key_bram` y lista para lectura. |
| **`4`** | `core_busy` | `1`: El acelerador está procesando cálculos en silicio. |
| `7:5` | *Reservado* | Siempre `000`. |
| **`15:8`**| **`iter_count`** | **Telemetría de iteraciones en tiempo real**: Número exacto de iteraciones ejecutadas (1 a 200). |
| `31:16`| *Reservado* | Siempre `0x0000`. |

---

### 3. `REG_K_FACTOR` (Offset `0x08`, Lectura/Escritura)

- Valor escalar de 32 bits con formato de punto fijo **Q10** (10 bits fraccionarios, escala $\times 1024$).
- Un valor de `38` equivale a $38 / 1024 \approx 0.0371$.
- Se utiliza únicamente cuando `REG_K_MODE == 0`.

---

### 4. `REG_K_MODE` (Offset `0x0C`, Lectura/Escritura)

| Valor | Modo de Operación |
| :---: | :--- |
| **`0`** | **Modo Escalar**: El datapath MDR utiliza el valor configurado en `REG_K_FACTOR` para todos los bloques. |
| **`1`** | **Modo Dinámico (Nominal)**: El datapath lee los factores $K_{dyn}$ individuales desde `ram_k` para cada uno de los 3.264 bloques. |

---

### 5. Memoria de Síndrome `syn_bram` (Offset `0x0100` a `0x099C`)

- Capacidad: **552 palabras de 32 bits** ($552 \times 32 = 17.664\text{ bits}$).
- Cada fila de paridad del LDPC ($Z = 384\text{ bits}$) está compuesta por 12 palabras de 32 bits.
- Hay 46 filas de paridad: $46 \times 12 = 552$ palabras.
- Puede ser leída y sobreescrita en caliente por MicroBlaze mediante lecturas/escrituras AXI.

---

### 6. Memoria de Clave `key_bram` (Offset `0x0A00` a `0x16BC`)

- Capacidad: **816 palabras de 32 bits** ($816 \times 32 = 26.112\text{ bits}$).
- La clave está formada por 68 columnas del código LDPC, donde cada columna tiene $Z = 384$ bits ($12$ palabras de 32 bits): $68 \times 12 = 816$ palabras.
- Al completarse la decodificación con éxito (`key_ready = 1`), el extractor hardware transfiere las 816 palabras en 816 ciclos de reloj desde `L_BRAM` a `key_bram`.
