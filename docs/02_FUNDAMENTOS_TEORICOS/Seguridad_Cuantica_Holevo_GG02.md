# Evaluación de Seguridad Cuántica en CV-QKD: Protocolo GG02 Heterodino y Cota de Holevo

> **Módulo Software**: `cvqkd_security.c` / `cvqkd_security.h`  
> **Arquitectura**: ARM Cortex-A9 MPCore @ 650 MHz (PYNQ-Z2)  
> **Marco Teórico**: GG02 sin conmutación (detección heterodina), reconciliación inversa, ataques colectivos, tamaño finito según Leverrier et al. (PRA 81, 062343, 2010)

---

## 1. Modelo del Sistema

1. **Alice** modula estados coherentes con una distribución gaussiana de varianza $V_A$ por cuadratura, en unidades de ruido de disparo (SNU). La varianza total del estado emitido es $V = V_A + 1$.

2. **El canal** tiene transmitancia $T = 10^{-\alpha L / 10}$ ($\alpha = 0.2$ dB/km) y ruido de exceso $\xi$ referido a su entrada:
   $$\chi_{\text{line}} = \frac{1}{T} - 1 + \xi$$

3. **Bob** mide **las dos cuadraturas a la vez** con un receptor heterodino (híbrido de 90° y dos detectores balanceados). Se modela con:
   - Eficiencia del receptor $\eta$ (sin contar el reparto 50:50 propio del heterodino).
   - Ruido electrónico $v_{el}$ de cada detector, en SNU de ese detector.
   - Calibración: 1 SNU = varianza de vacío de cada detector con solo el oscilador local ($N_0$ cuentas de ADC).
   - Ruido del detector referido a su entrada y ruido total referido a la entrada del canal:
     $$\chi_{\text{het}} = \frac{2 - \eta + 2 v_{el}}{\eta}, \qquad \chi_{\text{tot}} = \chi_{\text{line}} + \frac{\chi_{\text{het}}}{T}$$

Cada cuadratura medida por Bob es $y = t\,x + z$ con $t^2 = T\eta/2$ y $\text{Var}(z) = \sigma^2 = 1 + v_{el} + t^2 \xi$.

**Punto de trabajo** (coherente con el generador de MATLAB): bobina de 10 km ($T = 0.631$), $\eta = 0.6$, $v_{el} = 0.1$ SNU, $\xi = 0.01$ SNU y $V_A = 5$ SNU. Con el código LDPC BG1 de tasa $22/68$ esto da un SNR por cuadratura de 0.86 y $\beta \approx 0.72$, suficiente para que el decodificador converja con margen.

---

## 2. Estimación de Parámetros en Hardware

El estimador de Bob (`LLR_math_unit.sv`) usa las $m$ muestras sacrificadas de P y Q ($2m$ muestras reales):
$$\texttt{T\_FINAL} = \left(\frac{\text{Cov}(x, y)}{V_A}\right)^2 = t^2 = \frac{T\eta}{2}, \qquad \texttt{SIGMA\_SQ} = \text{Var}(y)$$

En la CPU: $\sigma^2 = \text{Var}(y) - t^2 V_A$ y $\xi = (\sigma^2 - 1 - v_{el}) / t^2$.

---

## 3. Información Mutua $I(A; B)$

Por cuadratura (dimensión), con $\text{SNR} = \dfrac{T \eta V_A}{2 + 2 v_{el} + T \eta \xi}$:
$$I(A; B) = \frac{1}{2} \log_2(1 + \text{SNR}) \quad [\text{bits/dimensión}]$$

Cada pulso aporta 2 dimensiones; el MDR 8D agrupa 4 pulsos.

---

## 4. Cota de Holevo $\chi(B; E)$

Para un modo con autovalor simpléctico $\lambda$, $S = g\left(\frac{\lambda - 1}{2}\right)$ con $g(x) = (x + 1) \log_2(x + 1) - x \log_2 x$.

**Antes de la detección** ($S(E) = S(AB)$):
$$A = V^2 (1 - 2T) + 2T + T^2 (V + \chi_{\text{line}})^2, \qquad B = T^2 (V \chi_{\text{line}} + 1)^2$$
$$\lambda_{1,2}^2 = \tfrac{1}{2} \left( A \pm \sqrt{A^2 - 4B} \right)$$

**Tras la medida heterodina de Bob** (detector de confianza, Lodewyck et al., PRA 76, 042305, 2007):
$$C = \frac{A \chi_{\text{het}}^2 + B + 1 + 2\chi_{\text{het}}\left(V\sqrt{B} + T(V + \chi_{\text{line}})\right) + 2T(V^2 - 1)}{T^2 (V + \chi_{\text{tot}})^2}, \qquad D = \left(\frac{V + \sqrt{B}\,\chi_{\text{het}}}{T(V + \chi_{\text{tot}})}\right)^2$$
$$\lambda_{3,4}^2 = \tfrac{1}{2} \left( C \pm \sqrt{C^2 - 4D} \right), \qquad \lambda_5 = 1$$

Por pulso, $\chi = \sum_{i=1,2} g\!\left(\frac{\lambda_i - 1}{2}\right) - \sum_{i=3,4} g\!\left(\frac{\lambda_i - 1}{2}\right)$; el código la reparte entre las 2 dimensiones del pulso. La expresión cerrada se ha validado frente a un cálculo gaussiano numérico independiente (error < $10^{-13}$).

---

## 5. Tasa de Clave Secreta

La información que la reconciliación deja a Alice y Bob se calcula con la **fuga real** del síndrome LDPC (no con una $\beta$ supuesta). En MDR los bits de Bob son uniformes ($H(U) = 1$ bit/dimensión):
$$\beta I(A;B) = 1 - \frac{\text{leak}_{EC}}{n} = 1 - \frac{46 \cdot 384}{26112} = 0.3235$$

**Asintótica**: $K_{\infty} = \beta I(A;B) - \chi(B;E)$ [bits/dimensión]; $\text{SKR} = 2 R_{\text{rep}} K$.

**Tamaño finito** (Leverrier 2010), con $z = \sqrt{2 \ln(2/\epsilon_{PE})} \approx 6.89$ para $\epsilon_{PE} = 10^{-10}$:
$$t_{\min} = t - z\sqrt{\frac{\sigma^2}{2m V_A}}, \qquad \sigma^2_{\max} = \sigma^2\left(1 + \frac{z}{\sqrt{m}}\right)$$
$$T_{\min} = \frac{2 t_{\min}^2}{\eta}, \qquad \xi_{\max} = \frac{\sigma^2_{\max} - 1 - v_{el}}{t_{\min}^2}$$
$$\Delta(n) = (2 \dim \mathcal{H}_X + 3)\sqrt{\frac{\log_2(2/\bar\epsilon)}{n}} + \frac{2}{n}\log_2\frac{1}{\epsilon_{PA}}, \qquad \dim \mathcal{H}_X = 2$$
$$K_{\text{finite}} = \beta I(A;B) - \chi(B;E)\big|_{T_{\min}, \xi_{\max}} - \Delta(n)$$

Longitud de la amplificación de privacidad (descontando también el hash de verificación):
$$\ell = \left\lfloor n K_{\text{finite}} - \log_2(1/\epsilon_{cor}) \right\rfloor$$

---

## 6. Política de Seguridad

| Condición | Veredicto |
|---|---|
| $1 - \text{leak}_{EC}/n \ge I(A;B)$ | ABORT: la reconciliación no puede converger |
| $\ell \le 0$ | ABORT: Holevo + tamaño finito no dejan clave |
| $\ell > 0$ | PASS: se extraen $\ell$ bits con amplificación de privacidad |

No existe aceptación "asintótica": una trama con $K_{\text{finite}} \le 0$ siempre se aborta.

### Evaluación por bloques de tramas

Con una sola trama ($n = 26\,112$ bits, $m = 13\,056$ muestras de estimación) la corrección de tamaño finito y el término $\log_2(1/\epsilon_{cor})$ superan a la clave: toda trama aislada se aborta. Por eso el firmware evalúa la seguridad **por bloques de $F$ tramas**: el acelerador procesa cada trama (MDR y síndrome), la CPU promedia $t = \sqrt{\texttt{T\_FINAL}}$ y $\text{Var}(y)$ de las $F$ tramas (cada una aporta las mismas muestras, así que es la estimación con todas las del bloque) y evalúa una vez con $m$, $n$ y $\text{leak}_{EC}$ multiplicados por $F$.

Clave del bloque con los valores verdaderos del punto de trabajo ($T = 0{,}631$, $\xi = 0{,}01$):

| $F$ (tramas) | $\ell$ (bits seguros del bloque) |
|---|---|
| 1 | 0 (ABORT) |
| 50 | 0 (ABORT) |
| 340 | 3 741 (umbral) |
| 500 | 77 299 |
| 1000 | 357 832 |

Cerca del umbral la fluctuación de la estimación decide: en simulación, con $F = 400$ se abortan un 30 % de los bloques sin ataque y con $F = 1000$ ninguno (clave mínima 225 000 bits en 20 semillas). El firmware usa $F = 1000$; una ventana de ataque de 10 tramas (1 % del bloque) basta para abortarlo. `m_samples` y `n_key_bits` son `uint32_t`, lo que limita un bloque a unas 160 000 tramas.

**Las tramas del bloque deben ser independientes.** Repetir la misma trama $F$ veces estrecha el intervalo de confianza sin acercar la estimación al valor real, y la clave resultante no es válida. Por eso la fase II del firmware genera cada trama en el ARM (`synth_frame`): una realización nueva del modelo de `tb_generador_master.m` sin ruido de fase. El ataque se modela como interceptar y reenviar con heterodino ($\xi = 2$ SNU).

**Suelo de ruido.** El ruido de disparo y el electrónico están calibrados, así que $\sigma^2 \ge 1 + v_{el}$. Una estimación por debajo es fluctuación estadística y se sube al suelo ($\xi = 0$) antes de calcular el peor caso. Esto solo puede reducir la clave.
