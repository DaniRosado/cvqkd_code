# Evaluación de Seguridad Cuántica en CV-QKD: Protocolo GG02 y Cota de Holevo

> **Módulo Software**: `cvqkd_security.c` / `cvqkd_security.h`  
> **Arquitectura**: ARM Cortex-A9 MPCore @ 650 MHz (PYNQ-Z2)  
> **Marco Teórico**: Grosshans-Grangier 2002 (GG02) con Reconciliación Inversa y Ataques Colectivos Asintóticos / Finitos  

---

## 1. Fundamentos del Protocolo GG02

En el protocolo de Distribución Cuántica de Claves en Variables Continuas (CV-QKD) propuesto por Grosshans y Grangier (2002):
1. **Alice** modula estados coherentes $|x_A + i p_A\rangle$ según una distribución gaussiana bivariada centrada en cero con varianza de modulación $V_A$ en unidades de ruido de disparo (*Shot Noise Units*, SNU):
   $$\text{Var}(x_A) = \text{Var}(p_A) = V_A$$
   La varianza total del estado emitido por Alice es $V = V_A + 1$.

2. **El Canal Cuántico** introduce:
   - Una transmitancia óptica $T \in [0, 1]$, correspondiente a una atenuación de fibra $\alpha = 0.20\text{ dB/km}$:
     $$T = 10^{-\frac{\alpha \cdot L}{10}}$$
   - Un ruido de exceso $\xi$ (en SNU), introducido por imperfecciones físicas o por las operaciones de interceptación del espía (Eva).
   - El ruido total referido al canal es:
     $$\chi_{\text{line}} = \frac{1}{T} - 1 + \xi$$

3. **Bob** mide las cuadraturas mediante un detector homodino balanceado caracterizado por:
   - Eficiencia cuántica de detección $\eta$ (típicamente $60\% = 0.60$).
   - Ruido electrónico $v_{el}$ en SNU (típicamente $0.10\text{ SNU}$).
   - Ruido referido al detector homodino:
     $$\chi_{\text{hom}} = \frac{1 - \eta + v_{el}}{\eta}$$
   - Ruido total referido a la entrada del canal:
     $$\chi_{\text{tot}} = \chi_{\text{line}} + \frac{\chi_{\text{hom}}}{T}$$

---

## 2. Información Mutua de Shannon $I(A; B)$

La relación señal a ruido (SNR) en el detector homodino de Bob es:
$$\text{SNR} = \frac{T \eta V_A}{1 + v_{el} + T \eta \xi}$$

Bajo reconciliación inversa (donde Bob define la clave secreta y Alice intenta reconciliarla), la información mutua entre Alice y Bob viene dada por la capacidad de Shannon del canal AWGN:
$$I(A; B) = \frac{1}{2} \log_2(1 + \text{SNR})$$

---

## 3. Cota de Holevo $\chi(B; E)$ bajo Ataques Colectivos

Bajo los teoremas de seguridad de Renner y Leverrier, los **ataques colectivos** representan la estrategia óptima de espionaje en el límite asintótico y de tamaño finito: Eva interactúa individualmente con cada pulso cuántico y retiene su memoria cuántica hasta el final del protocolo clásico.

La información máxima que Eva puede extraer sobre la medida de Bob está acotada superiormente por la **Cota de Holevo**:
$$\chi(B; E) = S(\rho_E) - \int p(y_B) S(\rho_E^{y_B}) \, dy_B$$

Dado que el sistema global formado por Alice, Bob y Eva es un estado puro ($\rho_{ABE}$ es puro), la entropía de Eva coincide con la entropía del estado bipartito de Alice y Bob:
$$S(\rho_E) = S(\rho_{AB})$$
$$S(\rho_E^{y_B}) = S(\rho_A^{y_B})$$

### 3.1. Entropía de Von Neumann para Estados Gaussianos Bosónicos
Para un modo con autovalor simpléctico $\lambda \ge 1$:
$$S = g\left(\frac{\lambda - 1}{2}\right)$$
donde la función entrópica bosónica $g(x)$ está definida por:
$$g(x) = (x + 1) \log_2(x + 1) - x \log_2(x)$$

### 3.2. Autovalores Simplécticos de la Matriz de Covarianza $\Gamma_{AB}$
La matriz de covarianza antes de la detección homodina tiene dos invariantes simplécticos:
$$\Delta = V^2 (1 - 2T) + 2T + T^2 (V + \chi_{\text{line}})^2$$
$$D = T^2 (V \chi_{\text{line}} + 1)^2$$

Los autovalores simplécticos $\lambda_{1,2}$ son:
$$\lambda_{1,2}^2 = \frac{1}{2} \left( \Delta \pm \sqrt{\Delta^2 - 4D} \right)$$

### 3.3. Autovalores Simplécticos Condicionales tras la Medida de Bob
Tras la medida de una cuadratura por el detector homodino de Bob, el estado condicional restante tiene autovalores simplécticos $\lambda_{3,4}$:
$$C = \frac{\Delta \chi_{\text{hom}} + V \sqrt{D} + T(V + \chi_{\text{line}})}{T(V + \chi_{\text{tot}})}$$
$$E = \frac{\sqrt{D}(V + \chi_{\text{hom}}\sqrt{D})}{T(V + \chi_{\text{tot}})}$$
$$\lambda_{3,4}^2 = \frac{1}{2} \left( C \pm \sqrt{C^2 - 4E} \right)$$

Finalmente, la cota de Holevo es:
$$\chi(B; E) = g\left(\frac{\lambda_1 - 1}{2}\right) + g\left(\frac{\lambda_2 - 1}{2}\right) - g\left(\frac{\lambda_3 - 1}{2}\right) - g\left(\frac{\lambda_4 - 1}{2}\right)$$

---

## 4. Tasa de Clave Secreta (*Secret Key Rate* - SKR)

### 4.1. Límite Asintótico
Con una eficiencia de reconciliación LDPC $\beta = 0.95$ (95% de la capacidad de Shannon):
$$K_{\text{asymp}} = \beta I(A; B) - \chi(B; E) \quad [\text{bits / símbolo}]$$

A una tasa de repetición del transmisor láser $R_{\text{rep}} = 1.0\text{ GHz}$:
$$\text{SKR}_{\text{asymp}} = R_{\text{rep}} \cdot K_{\text{asymp}} \quad [\text{Mbps}]$$

### 4.2. Corrección por Efectos de Tamaño Finito (Finite-Size Effects)
Cuando se sacrifican $m = 13.056$ muestras para estimar $T$ y $\xi$, existe una incertidumbre estadística acotada por el parámetro de fallo $\epsilon_{\text{PE}} = 10^{-10}$ ($z_{\epsilon} = \sqrt{2 \ln(2/\epsilon_{\text{PE}})} \approx 6.47$ desviaciones estándar).
Los parámetros en el peor caso son:
$$T_{\text{worst}} = T - \Delta T_{\text{PE}}$$
$$\xi_{\text{worst}} = \xi + \Delta \xi_{\text{PE}}$$

La tasa finita corregida incorpora la penalización por la propiedad de equipartición asintótica (AEP):
$$K_{\text{finite}} = \beta I(A; B)_{\text{worst}} - \chi(B; E)_{\text{worst}} - \Delta_{\text{AEP}}$$

---

## 5. Política de Seguridad y Defensa Activa

En la aplicación de streaming de Bob, el procesador evalúa $K$ en cada trama:

$$\text{Veredicto} = \begin{cases} 
\mathbf{PASS} & \text{si } K > 0 \implies \text{Canal seguro, se autorizan } \lfloor n \cdot K \rfloor \text{ bits para Alice.} \\
\mathbf{ABORT} & \text{si } K \le 0 \implies \text{Alerta de intrusión de Eva, trama destruida inmediatamente.}
\end{cases}$$
