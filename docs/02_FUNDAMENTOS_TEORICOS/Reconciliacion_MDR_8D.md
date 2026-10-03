# Fundamentos Teóricos: Reconciliación Multidimensional (8D MDR)

> **Módulos RTL asociados**: `mdr_alice_top.sv`, `mdr_alice_fsm.sv`, `mdr_alice_datapath.sv`  
> **Álgebra**: Matrices ortogonales de Hurwitz-Radon sobre $\mathbb{R}^8$  
> **Formato Aritmético Hardware**: Coordenadas $X$ (16 bits), Mensaje $m$ (Q24/Q21), Factor $K$ (Q10)  

---

## 🎯 Por qué Reconciliación en Dimensión 8

En protocolos de CV-QKD basados en modulación Gaussiana (GG02), Alice modula estados coherentes continuos y Bob realiza detección heterodina (mide P y Q a la vez). Para convertir estas variables continuas gaussianas correlacionadas en una clave binaria secreta compartida a distancias largas ($>25\text{ km}$), la SNR del canal es típicamente muy baja ($\text{SNR} < 0\text{ dB}$).

La reconciliación multidimensional (MDR), introducida por Leverrier et al. (2008), mapea el canal gaussiano continuo a un **canal virtual BSC (Binary Symmetric Channel)** con ruido gaussiano añadido sin revelar información sobre la clave.

Según el **teorema de Hurwitz-Radon**, el número máximo de matrices ortogonales anticonmutativas lineales e independientes de dimensión $d$ es $d-1$ **únicamente para las dimensiones $d \in \{1, 2, 4, 8\}$** (asociadas a los números reales, complejos, cuaterniones y octoniones). Por tanto, la dimensión **$d = 8$** es la máxima dimensión euclídea posible que permite construir una rotación ortogonal exacta sin pérdida de energía ni distorsión de la modulación.

---

## 📐 Formulación Matemática

Para cualquier vector $\mathbf{v} = (v_1, v_2, \dots, v_8) \in \mathbb{R}^8$, se define la matriz de Hurwitz-Radon $M(\mathbf{v}) \in \mathbb{R}^{8 \times 8}$, que satisface de forma estricta:

$$M(\mathbf{v}) M(\mathbf{v})^T = \|\mathbf{v}\|^2 I_8$$

Donde la primera fila de $M(\mathbf{v})$ es exactamente $\mathbf{v}$.

### Protocolo de Reconciliación Inversa (Reverse Reconciliation):
1. **Generación en Bob**:
   - Bob recibe el bloque continuo $\mathbf{y}_i \in \mathbb{R}^8$.
   - Normaliza el vector: $\mathbf{y}_{\text{norm}} = \frac{\mathbf{y}_i}{\|\mathbf{y}_i\|}$.
   - Genera 8 bits aleatorios independientes de clave $\mathbf{b}_i \in \{0, 1\}^8$, transformados a antipodal: $C_{i,k} = 1 - 2 b_{i,k} \in \{-1, +1\}$.
   - Calcula el mensaje público de rotación $\mathbf{m}_i \in \mathbb{R}^8$:
     $$\mathbf{m}_i = M(\mathbf{y}_{\text{norm}})^T \cdot \mathbf{C}_i$$
   - Bob transmite $\mathbf{m}_i$ a Alice por el canal clásico público.
2. **Procesamiento en Alice**:
   - Alice construye la matriz de Hurwitz-Radon de sus coordenadas $M(\mathbf{x}_i)$.
   - Calcula el vector proyectado continuo $\mathbf{u}_i \in \mathbb{R}^8$:
     $$\mathbf{u}_i = M(\mathbf{x}_i) \cdot \mathbf{m}_i$$
   - Multiplicando las expresiones:
     $$\mathbf{u}_i = M(\mathbf{x}_i) M(\mathbf{y}_{\text{norm}})^T \mathbf{C}_i = \langle \mathbf{x}_i, \mathbf{y}_{\text{norm}} \rangle \mathbf{C}_i + \mathbf{e}_i$$
   - Dado que el producto escalar $\langle \mathbf{x}_i, \mathbf{y}_{\text{norm}} \rangle > 0$, el signo de $u_{i,k}$ coincide con $C_{i,k} = 1 - 2 b_{i,k}$ con una probabilidad dictada por la SNR del canal.

---

## 🔢 Cálculo de los Log-Likelihood Ratios (LLR)

La fiabilidad de cada bit (LLR) que alimenta al decodificador LDPC se calcula con la distribución condicional gaussiana. Con detección heterodina cada cuadratura de Bob es $y = t\,x + z$, con $t = \sqrt{T\eta/2}$ y ruido de varianza $\sigma_z^2$:

$$\text{LLR}_{i,k} = \ln \left( \frac{P(b_{i,k} = 0 \mid \mathbf{x}_i, \mathbf{m}_i)}{P(b_{i,k} = 1 \mid \mathbf{x}_i, \mathbf{m}_i)} \right) = \frac{2 t}{\sigma_z^2} \|\mathbf{y}_i\| u_{i,k}$$

Definiendo el factor de calibración dinámico $K_{dyn, i}$, $\mathbf{LLR}_{i,k} = K_{dyn, i} \cdot u_{i,k}$.

En la implementación (modelo de MATLAB y hardware) se usa $K_{dyn, i} = 2\|\mathbf{y}_i\| / \sigma_B^2$, con $\sigma_B^2 = \text{Var}(y)$ la varianza total por cuadratura medida por el estimador y $\mathbf{x}$ sin normalizar. Es el LLR exacto multiplicado por un factor constante en toda la trama ($\sigma_z^2 / (t\,\sigma_B^2)$, con todas las magnitudes en las mismas unidades): el Min-Sum es invariante a una escala común salvo por la cuantización y la saturación a 8 bits, que es lo que fija este factor.

En el hardware de Alice, el módulo `mdr_alice_datapath.sv` ejecuta esta multiplicación en aritmética de punto fijo:
- $u_{i,k}$ en formato con signo de 42 bits (acumulación de productos DSP48E1).
- $K_{dyn, i}$ en formato con signo Q10 (10 bits fraccionarios).
- Salida LLR saturada a 8 bits con signo y magnitud en el rango $[-127, +127]$.
