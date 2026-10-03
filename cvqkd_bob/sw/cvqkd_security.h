/******************************************************************************
 *  TFG: Acelerador Hardware CV-QKD - Módulo de Seguridad Cuántica
 *  Archivo: cvqkd_security.h
 *
 *  Descripción:
 *  Definiciones y estructuras para la evaluación estricta de la seguridad
 *  cuántica bajo ataques colectivos (GG02 sin conmutación: detección heterodina
 *  de P y Q, reconciliación inversa).
 *  Calcula la Cota de Holevo chi(B; E), información mutua I(A; B),
 *  Secret Key Rate (SKR) asintótico y de tamaño finito en la CPU de Bob (Zynq).
 ******************************************************************************/

#ifndef CVQKD_SECURITY_H
#define CVQKD_SECURITY_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Parámetros físicos y de calibración del sistema CV-QKD */
typedef struct {
    double V_A;          /* Varianza de modulación de Alice en SNU */
    double eta;          /* Eficiencia del receptor de Bob (sin el 50:50 del heterodino) */
    double v_el;         /* Ruido electrónico de cada detector, en SNU de ese detector */
    double fiber_alpha;  /* Atenuación de la fibra óptica en dB/km (típico: 0.20 dB/km) */
    double rep_rate_hz;  /* Frecuencia de repetición del láser en Hz (típico: 1.0e9 = 1 Gbaud) */
    double N0_adc_var;   /* Varianza ADC de vacío de cada detector (solo LO) = 1 SNU */
    uint32_t m_samples;    /* Pulsos sacrificados para estimación de parámetros (13.056) */
    uint32_t n_key_bits;   /* Bits brutos de clave por trama (26.112 = 2 por pulso) */
    uint32_t leak_ec_bits; /* Bits revelados en la corrección de errores (síndrome: 46 x 384 = 17.664) */
    double epsilon_pe;   /* Fallo de la estimación de parámetros (1e-10) */
    double epsilon_sm;   /* Suavizado de la entropía min (1e-10) */
    double epsilon_pa;   /* Fallo de la amplificación de privacidad (1e-10) */
    double epsilon_cor;  /* Fallo de la verificación de clave por hash (1e-10) */
} cvqkd_security_params_t;

/* Resultados de la evaluación de seguridad en tiempo real */
typedef struct {
    /* Parámetros de canal medidos por el hardware */
    double T;                 /* Transmitancia estimada del canal óptico [0.0 - 1.0] */
    double loss_db;           /* Pérdida de canal en dB */
    double distance_km;       /* Distancia equivalente de fibra SMF-28 en km */
    double xi_snu;            /* Ruido de exceso del canal en SNU (Shot Noise Units) */
    double snr_linear;        /* Relación señal a ruido lineal */
    double snr_db;            /* Relación señal a ruido en dB */

    /* Magnitudes de teoría de la información cuántica */
    double I_AB;              /* Información mutua Alice-Bob: I(A;B) [bits/dimensión] */
    double beta_eff;          /* Eficiencia real de reconciliación: (1 - leak_ec/n) / I(A;B) */
    double chi_BE;            /* Cota de Holevo sobre la información de Eva: chi(B;E) [bits/dimensión] */
    double K_asymp;           /* Tasa de clave secreta asintótica [bits/dimensión] */
    double skr_asymp_mbps;    /* Tasa de clave neta a la tasa de repetición del láser [Mbps] */

    /* Análisis de tamaño finito (Finite-Size Effects) */
    double delta_pe_T;        /* Margen de incertidumbre estadística en transmitancia (T - T_worst) */
    double delta_pe_xi;       /* Margen de incertidumbre estadística en ruido (xi_worst - xi) */
    double T_worst;           /* Peor caso de transmitancia */
    double xi_worst;          /* Peor caso de exceso de ruido */
    double delta_n;           /* Corrección de tamaño finito Delta(n) [bits/dimensión] */
    double K_finite;          /* Tasa de clave secreta con tamaño finito [bits/dimensión] (puede ser < 0) */
    double skr_finite_mbps;   /* Tasa neta de clave con tamaño finito [Mbps] */

    /* Amplificación de Privacidad (Privacy Amplification) */
    uint32_t n_key_bits;      /* Bits brutos de clave evaluados (trama o bloque) */
    uint32_t pa_output_bits;  /* Bits seguros a extraer tras amplificación de privacidad */
    double pa_rate;           /* Ratio de compresión de la función hash de Toeplitz */

    /* Veredicto de Seguridad */
    bool is_secure;           /* true = PASS (Canal seguro), false = ABORT (Ataque detectado) */
    const char *status_msg;   /* Mensaje explicativo del estado */
} cvqkd_security_result_t;

/* Inicializar parámetros de canal por defecto */
void cvqkd_security_init_defaults(cvqkd_security_params_t *params);

/* Función de entropía de Von Neumann: g(x) = (x+1)log2(x+1) - x log2(x) */
double cvqkd_von_neumann_entropy(double x);

/*
 * Evalúa la seguridad de una trama a partir de los registros de hardware de Bob:
 *   - T_q16: Registro BOB_REG_T_FINAL = (Cov/V_A)^2 = T*eta/2 en Q16.16
 *   - sigma_sq_hw: Registro BOB_REG_SIGMA_SQ (varianza en unidades de ADC)
 */
bool cvqkd_evaluate_frame_security(
    const cvqkd_security_params_t *params,
    int32_t T_q16,
    int32_t sigma_sq_hw,
    cvqkd_security_result_t *result
);

/* Imprime un informe de seguridad estructurado (compatible con xil_printf y printf) */
void cvqkd_print_security_report(const cvqkd_security_result_t *res);

#ifdef __cplusplus
}
#endif

#endif /* CVQKD_SECURITY_H */
