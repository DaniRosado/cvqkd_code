# Contexto General del Proyecto: Hardware para CV-QKD (GG02)

## 1. Visión General del Proyecto
Este proyecto consiste en la implementación en hardware (SystemVerilog) del procesamiento digital de señales (DSP) y la reconciliación de información para un sistema de Distribución Cuántica de Claves de Variable Continua (CV-QKD), específicamente basado en el protocolo GG02. Forma parte de un Trabajo de Fin de Grado (TFG) en Ingeniería Industrial.

El sistema se divide en varios bloques fundamentales: procesamiento en el receptor (Bob), decodificación de corrección de errores en el transmisor (Alice) mediante LDPC, reconciliación multidimensional (MDR) y un modelo de referencia *Golden Model* en MATLAB.

## 2. Estructura del Repositorio
El código está organizado en cuatro directorios principales:

* **`cvqkd_matlab/`**: Contiene el modelo matemático de referencia (Golden Model). Simula el canal cuántico, el ruido, y genera los vectores de prueba (ficheros `.txt`) que luego consumen los testbenches de SystemVerilog.
* **`cvqkd_bob/`**: Contiene el DSP del receptor. 
    * Responsabilidades: Demultiplexación de tramas (Pilotos vs. Datos), estimación de fase, compensación de fase, estimación de parámetros del canal (Varianza, Covarianza, SNR) y cálculo inicial de la relación de verosimilitud logarítmica (LLR) y el síndrome.
* **`cvqkd_alice/`**: Contiene el decodificador LDPC (Low-Density Parity-Check).
    * Responsabilidades: Recibir los LLRs del canal y el síndrome generado por Bob, y ejecutar el algoritmo *Min-Sum* por capas (Layered Min-Sum) para corregir los errores cuánticos y reconciliar la clave.
* **`cvqkd_mdr/`**: Contiene la lógica de Reconciliación Multidimensional (MDR) en 8 dimensiones.
    * Responsabilidades: Normalización, rotaciones y mapeo para transformar variables gaussianas en variables compatibles con la decodificación binaria.

## 3. Arquitectura del Decodificador LDPC (Alice)
El decodificador LDPC es el núcleo computacional más complejo del proyecto. Detalles clave para su comprensión:
* **Algoritmo:** Layered Min-Sum con factor de atenuación Alpha (Scaled Min-Sum, típicamente `norm_mag = raw_mag - (raw_mag >> 2)`).
* **Tamaño de la Matriz:** Basada en matrices tipo 5G BG1 (adaptada). Dimensiones de submatriz $Z = 384$. La matriz base tiene 46 filas y 68 columnas. Total de variables: $26.112$ bits.
* **Precisión de datos:** Parametrizado por `W` (típicamente 16 bits para LLRs y mensajes, formato signo-magnitud).
* **Flujo de datos (Datapath):** * Se instancian 384 VNUs (Variable Node Units) y 384 CNUs (Check Node Units) en paralelo.
    * Se utilizan *Barrel Shifters* para enrutar los mensajes según la matriz de permutación (almacenada en `bg_rom_pkg.sv`).
* **Parada Temprana (Early Termination):** En QKD, el síndrome objetivo **no es cero**. La CNU se inicializa con el bit del síndrome aleatorio de Bob (`target_syndrome_bit`). Si la decodificación converge, la salida residual del CNU (`row_syndrome`) debe ser todo ceros (`'0`). La FSM monitoriza esto para detener las iteraciones antes de `MAX_ITER`.

## 4. Convenciones de Diseño en SystemVerilog
Para mantener la coherencia y evitar bugs de simulación/síntesis, el código sigue estas reglas estrictas:
* **Pipelines y BRAMs:** Las memorias BRAM de Xilinx/FPGA tienen 1 ciclo de latencia de lectura. Las señales de control (como `Valid`, `Write Enable` y las direcciones `Addr`) se propagan mediante registros de retardo (sufijo `_q` o `_prev`) para asegurar que la escritura se alinea con la llegada de los datos.
* **Variables Combinacionales vs Secuenciales:** En buses complejos (como la transmisión VNU a CNU), se evita la mezcla de fases usando el bus puramente combinacional actual para las asignaciones lógicas, y registrando solo en las fronteras de reloj.
* **FSM (Máquina de Estados):** Separación clara entre `ST_LOAD` (carga inicial de LLRs), `ST_READ_LAYER`, `ST_WRITE_LAYER` y `ST_WRITE_DRAIN` (necesario para dar tiempo a escribir la última columna procesada debido al retardo de pipeline).
* **Endianness:** Al cargar síndromes o LLRs generados por MATLAB mediante `$readmemb`, se presta especial atención al mapeo de bits (MSB vs LSB) en los bucles `generate` del hardware (usando operadores de inversión `{<<{}}` o indexado invertido `Z-1-i` en los testbenches según proceda).

## 5. Flujo de Trabajo y Verificación (Workflow)
El debugging y la verificación se realizan mediante un flujo híbrido:
1.  **Generación de Datos (MATLAB):** Los scripts (ej. `tb_generador_master.m`) simulan el enlace de fibra óptica, atenuación cuántica y ruido, escupiendo el estado interno en `.txt` (ej. `u_bits.txt`, `expected_syndrome.txt`, `bob_key_ref.txt`).
2.  **Simulación RTL (Vivado/Questa/Verilator):** Los testbenches superiores (`tb_ldpc_top_system.sv`, `tb_cvqkd_bob_dsp_top.sv`) leen estos `.txt` usando rutas absolutas o relativas.
3.  **Monitores de Depuración:** Los testbenches incluyen bloques `always @(posedge clk)` que actúan como "sondas" para contar coincidencias y errores (`mismatches`) comparando la salida de los módulos con las referencias de MATLAB al vuelo, permitiendo detectar caídas de la tasa de error bit (BER) a cero sin necesidad de revisar pesadas formas de onda manuales.

## 6. Instrucciones para la Inteligencia Artificial Asistente
Cuando se te pida analizar, depurar o extender este código, asume lo siguiente:
* El objetivo final es hardware sintetizable para FPGA/ASIC; prioriza siempre descripciones síncronas claras y evita bucles combinacionales (latch inferidos).
* Si modificas la latencia de un módulo (ej. añadiendo un ciclo de pipeline para relajar el *timing*), debes actualizar la máquina de estados o los registros de control equivalentes en el módulo superior (`_top`) para mantener la alineación de las validaciones de memoria.
* Conoce el concepto de reconciliación en CV-QKD: Bob define el síndrome y Alice debe converger hacia la misma palabra clave de Bob. El canal siempre tiene ruido y atenuación óptica; la robustez del LDPC bajo SNR baja es crítica.