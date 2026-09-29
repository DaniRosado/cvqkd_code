/******************************************************************************
 *  TFG: Acelerador Hardware CV-QKD - Módulo de Seguridad Cuántica
 *  Archivo: cvqkd_security.h
 *
 *  Descripción:
 *  Definiciones y estructuras para la evaluación estricta de la seguridad
 *  cuántica bajo ataques colectivos (Protocolo GG02 con reconciliación inversa).
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
    double V_A;          /* Varianza de modulación de Alice en SNU (típico: 4.0 a 5.0) */
    double eta;          /* Eficiencia cuántica de los fotodiodos de Bob (típico: 0.60) */
    double v_el;         /* Ruido electrónico del detector homodino en SNU (típico: 0.05) */
    double beta;         /* Eficiencia de reconciliación LDPC (típico: 0.95 = 95%) */
    double fiber_alpha;  /* Atenuación de la fibra óptica en dB/km (típico: 0.20 dB/km) */
    double rep_rate_hz;  /* Frecuencia de repetición del láser en Hz (típico: 1.0e9 = 1 Gbaud) */
    double N0_adc_var;   /* Varianza ADC correspondiente a 1 SNU (Shot Noise Unit) */
    uint32_t m_samples;  /* Muestras sacrificadas para estimación de parámetros (13.056) */
    uint32_t n_key_bits; /* Bits brutos de clave por trama (26.112) */
    double epsilon_pe;   /* Parámetro de seguridad para fluctuaciones estadísticas (1e-10) */
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
    double I_AB;              /* Información mutua Alice-Bob: I(A;B) [bits/símbolo] */
    double chi_BE;            /* Cota de Holevo sobre la información de Eva: chi(B;E) [bits/símbolo] */
    double K_asymp;           /* Tasa de clave secreta asintótica [bits/símbolo] */
    double skr_asymp_mbps;    /* Tasa de clave neta a la tasa de repetición del láser [Mbps] */

    /* Análisis de tamaño finito (Finite-Size Effects) */
    double delta_pe_T;        /* Margen de incertidumbre estadística en transmitancia */
    double delta_pe_xi;       /* Margen de incertidumbre estadística en ruido */
    double T_worst;           /* Peor caso de transmitancia */
    double xi_worst;          /* Peor caso de exceso de ruido */
    double K_finite;          /* Tasa de clave secreta con tamaño finito [bits/símbolo] */
    double skr_finite_mbps;   /* Tasa neta de clave con tamaño finito [Mbps] */

    /* Amplificación de Privacidad (Privacy Amplification) */
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
 *   - T_q16: Registro BOB_REG_T_FINAL en formato punto fijo Q16.16
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
