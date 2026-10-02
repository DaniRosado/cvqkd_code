/******************************************************************************
 *  TFG: Acelerador Hardware CV-QKD - Módulo de Seguridad Cuántica
 *  Archivo: cvqkd_security.c
 *
 *  Descripción:
 *  Implementación rigurosa de la teoría de la información cuántica para CV-QKD:
 *    - Información mutua Shannon I(A; B)
 *    - Autovalores simplécticos de matrices de covarianza de estados gaussianos
 *    - Cota de Holevo chi(B; E) bajo ataques colectivos
 *    - Corrección de fluctuaciones estadísticas por tamaño finito (Leverrier et al.)
 *    - Cómputo de amplificación de privacidad y veredicto de seguridad PASS/ABORT
 ******************************************************************************/

#include "cvqkd_security.h"
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

#if defined(__arm__) && !defined(__linux__)
    #include "xil_printf.h"
    #define PRINTF xil_printf
#elif defined(__MICROBLAZE__)
    #include "xil_printf.h"
    #define PRINTF xil_printf
#else
    #define PRINTF printf
#endif

#ifndef M_LN2
#define M_LN2 0.693147180559945309417
#endif

/* Entropía de Von Neumann para estados gaussianos bosónicos */
double cvqkd_von_neumann_entropy(double x) {
    if (x <= 1.0e-12) {
        return 0.0;
    }
    /* g(x) = (x+1)*log2(x+1) - x*log2(x) */
    double term1 = (x + 1.0) * (log(x + 1.0) / M_LN2);
    double term2 = x * (log(x) / M_LN2);
    return term1 - term2;
}

/* Configuración de parámetros nominales de canal y calibración */
void cvqkd_security_init_defaults(cvqkd_security_params_t *params) {
    if (!params) return;
    params->V_A         = 4.0;       /* 4.0 SNU de modulación gaussiana en Alice */
    params->eta         = 0.60;      /* 60% de eficiencia cuántica en homodino de Bob */
    params->v_el        = 0.10;      /* 0.10 SNU de ruido electrónico en Bob (calibración física) */
    params->fiber_alpha = 0.20;      /* 0.20 dB/km de atenuación en fibra SMF-28 */
    params->rep_rate_hz = 1.0e9;     /* Láser a 1.0 Gbaud (1 GHz) */
    params->N0_adc_var  = 10000.0;   /* 10.000 cuentas de varianza ADC = 1 SNU */
    params->m_samples   = 13056;     /* 13.056 muestras sacrificadas (50% de la trama) */
    params->n_key_bits  = 26112;     /* 26.112 bits útiles por trama */
    params->leak_ec_bits = 46 * 384; /* Síndrome LDPC BG1 (Z = 384) enviado a Alice */
    params->epsilon_pe  = 1.0e-10;
    params->epsilon_sm  = 1.0e-10;
    params->epsilon_pa  = 1.0e-10;
    params->epsilon_cor = 1.0e-10;
}

/*
 * Función auxiliar interna para calcular Holevo chi(B; E) dados T y xi
 */
static void compute_holevo_and_mutual(
    double T, double xi, double V_A, double eta, double v_el,
    double *out_IAB, double *out_chiBE, double *out_snr
) {
    double V = V_A + 1.0;
    double chi_line = 1.0 / T - 1.0 + xi;
    double chi_hom  = (1.0 - eta + v_el) / eta;
    double chi_tot  = chi_line + chi_hom / T;

    /* SNR e Información Mutua */
    double snr = (T * eta * V_A) / (1.0 + v_el + T * eta * xi);
    if (snr < 1.0e-9) snr = 1.0e-9;
    double I_AB = 0.5 * (log(1.0 + snr) / M_LN2);

    /* Autovalores simplécticos de Gamma_AB antes de la detección */
    double A = (V * V) * (1.0 - 2.0 * T) + 2.0 * T + (T * T) * pow(V + chi_line, 2.0);
    double B = pow(T * (V * chi_line + 1.0), 2.0);
    double disc1 = A * A - 4.0 * B;
    if (disc1 < 0.0) disc1 = 0.0;

    double sqrt_disc1 = sqrt(disc1);
    double l1_sq = 0.5 * (A + sqrt_disc1);
    double l2_sq = 0.5 * (A - sqrt_disc1);
    double l1 = sqrt((l1_sq > 1.0) ? l1_sq : 1.0);
    double l2 = sqrt((l2_sq > 1.0) ? l2_sq : 1.0);

    /* Autovalores simplécticos condicionales tras la medida homodina de Bob */
    double sqrt_B = sqrt(B);
    double denom = T * (V + chi_tot);
    double C = (A * chi_hom + V * sqrt_B + T * (V + chi_line)) / denom;
    double D = sqrt_B * (V + chi_hom * sqrt_B) / denom;
    double disc2 = C * C - 4.0 * D;
    if (disc2 < 0.0) disc2 = 0.0;

    double sqrt_disc2 = sqrt(disc2);
    double l3_sq = 0.5 * (C + sqrt_disc2);
    double l4_sq = 0.5 * (C - sqrt_disc2);
    double l3 = sqrt((l3_sq > 1.0) ? l3_sq : 1.0);
    double l4 = sqrt((l4_sq > 1.0) ? l4_sq : 1.0);

    /* Cota de Holevo chi(B; E) = S(E) - S(E | y_B) */
    double chi_BE = cvqkd_von_neumann_entropy((l1 - 1.0) * 0.5)
                  + cvqkd_von_neumann_entropy((l2 - 1.0) * 0.5)
                  - cvqkd_von_neumann_entropy((l3 - 1.0) * 0.5)
                  - cvqkd_von_neumann_entropy((l4 - 1.0) * 0.5);

    if (chi_BE < 0.0) chi_BE = 0.0;

    *out_IAB   = I_AB;
    *out_chiBE = chi_BE;
    *out_snr   = snr;
}

/*
 * Evaluación de seguridad de la trama en tiempo real
 */
bool cvqkd_evaluate_frame_security(
    const cvqkd_security_params_t *params,
    int32_t T_q16,
    int32_t sigma_sq_hw,
    cvqkd_security_result_t *result
) {
    if (!params || !result) return false;
    *result = (cvqkd_security_result_t){ .status_msg = "" };

    const double V_A  = params->V_A;
    const double eta  = params->eta;
    const double v_el = params->v_el;
    const double m    = (double)params->m_samples;
    const double n    = (double)params->n_key_bits;

    /* 1. Estimadores puntuales a partir de los registros hardware */
    /* T_FINAL (LLR_math_unit.sv) es T*eta en Q16.16; el estimador natural es t = sqrt(T*eta) */
    double T_eta = (double)T_q16 / 65536.0;
    if (T_eta < 1.0e-5) T_eta = 1.0e-5;
    if (T_eta > eta)    T_eta = eta;
    double t_hat = sqrt(T_eta);

    double T_est = T_eta / eta;
    result->T           = T_est;
    result->loss_db     = -10.0 * log10(T_est);
    result->distance_km = result->loss_db / params->fiber_alpha;

    /* Varianza condicional sigma^2 = Var(B) - T*eta*V_A = 1 + v_el + T*eta*xi (en SNU) */
    double var_B  = (double)sigma_sq_hw / params->N0_adc_var;
    double sigma2 = var_B - T_eta * V_A;
    double xi = (sigma2 - 1.0 - v_el) / T_eta;
    if (xi < 0.0) xi = 0.0; /* Sin ruido de exceso físico negativo */
    result->xi_snu = xi;

    /* 2. Peor caso de tamaño finito (Leverrier, Grosshans, Grangier, PRA 81, 062343, 2010) */
    /* z = sqrt(2 ln(2/eps_PE)) es una cota superior de z_{eps_PE/2} (6.89 para 1e-10) */
    double z = sqrt(2.0 * log(2.0 / params->epsilon_pe));
    double t_min      = t_hat - z * sqrt(sigma2 / (m * V_A));
    double sigma2_max = sigma2 * (1.0 + z * sqrt(2.0 / m));
    if (sigma2 <= 0.0 || t_min <= 0.0) {
        result->status_msg = "ESTIMACION INVALIDA: varianza o transmitancia fuera de rango. TRAMA ABORTADA.";
        return false;
    }
    double T_eta_min = t_min * t_min;
    double xi_worst  = (sigma2_max - 1.0 - v_el) / T_eta_min;
    if (xi_worst < 0.0) xi_worst = 0.0;

    result->T_worst     = T_eta_min / eta;
    result->xi_worst    = xi_worst;
    result->delta_pe_T  = T_est - result->T_worst;
    result->delta_pe_xi = xi_worst - xi;

    /* 3. Información accesible a cada parte */
    double I_AB = 0.0, chi_BE = 0.0, snr = 0.0;
    compute_holevo_and_mutual(T_est, xi, V_A, eta, v_el, &I_AB, &chi_BE, &snr);
    double I_AB_worst = 0.0, chi_BE_worst = 0.0, snr_worst = 0.0;
    compute_holevo_and_mutual(result->T_worst, xi_worst, V_A, eta, v_el,
                              &I_AB_worst, &chi_BE_worst, &snr_worst);

    /* beta*I(A;B) = H(U) - leak_EC/n. En MDR los bits u de Bob son uniformes: H(U) = 1 bit/símbolo */
    double rate_ec = 1.0 - (double)params->leak_ec_bits / n;

    result->snr_linear = snr;
    result->snr_db     = 10.0 * log10(snr);
    result->I_AB       = I_AB;
    result->beta_eff   = rate_ec / I_AB;
    result->chi_BE     = chi_BE;
    result->K_asymp    = rate_ec - chi_BE;
    if (result->K_asymp < 0.0) result->K_asymp = 0.0;
    result->skr_asymp_mbps = (params->rep_rate_hz * result->K_asymp) / 1.0e6;

    /* Delta(n) = 7 sqrt(log2(2/eps_sm)/n) + (2/n) log2(1/eps_PA) */
    result->delta_n  = 7.0 * sqrt(log2(2.0 / params->epsilon_sm) / n)
                     + (2.0 / n) * log2(1.0 / params->epsilon_pa);
    result->K_finite = rate_ec - chi_BE_worst - result->delta_n;
    result->skr_finite_mbps = (result->K_finite > 0.0)
                            ? (params->rep_rate_hz * result->K_finite) / 1.0e6 : 0.0;

    /* 4. Veredicto y longitud de la amplificación de privacidad.
     * Además de la fuga del síndrome se descuentan los bits del hash de verificación. */
    double pa_bits = floor(n * result->K_finite - ceil(log2(1.0 / params->epsilon_cor)));

    if (result->beta_eff >= 1.0) {
        result->status_msg = "TASA LDPC > I(A;B): la reconciliacion no puede converger. TRAMA ABORTADA.";
    } else if (pa_bits <= 0.0) {
        result->status_msg = "ALERTA DE INTRUSION: K_finite <= 0 (Holevo + tamano finito). TRAMA ABORTADA.";
    } else {
        result->is_secure      = true;
        result->status_msg     = "CANAL SEGURO: K_finite > 0. Clave autorizada.";
        result->pa_output_bits = (uint32_t)pa_bits;
        result->pa_rate        = pa_bits / n;
    }

    return result->is_secure;
}

/*
 * Helper para imprimir un valor flotante con número fijo de decimales
 * tanto en xil_printf como en printf convencional.
 */
static void print_float_val(const char *prefix, double val, const char *suffix, int decimals) {
#if defined(__arm__) && !defined(__linux__)
    int mult = 1;
    for (int k = 0; k < decimals; k++) mult *= 10;
    int sign = (val < 0.0) ? -1 : 1;
    double abs_val = val * (double)sign;
    int int_part = (int)abs_val;
    int frac_part = (int)((abs_val - (double)int_part) * (double)mult + 0.5);
    if (frac_part >= mult) {
        int_part += 1;
        frac_part -= mult;
    }
    if (decimals == 1) {
        PRINTF("%s%s%d.%01d%s", prefix, (sign < 0) ? "-" : "", int_part, frac_part, suffix);
    } else if (decimals == 2) {
        PRINTF("%s%s%d.%02d%s", prefix, (sign < 0) ? "-" : "", int_part, frac_part, suffix);
    } else if (decimals == 3) {
        PRINTF("%s%s%d.%03d%s", prefix, (sign < 0) ? "-" : "", int_part, frac_part, suffix);
    } else {
        PRINTF("%s%s%d.%04d%s", prefix, (sign < 0) ? "-" : "", int_part, frac_part, suffix);
    }
#else
    if (decimals == 1) {
        printf("%s%.1f%s", prefix, val, suffix);
    } else if (decimals == 2) {
        printf("%s%.2f%s", prefix, val, suffix);
    } else if (decimals == 3) {
        printf("%s%.3f%s", prefix, val, suffix);
    } else {
        printf("%s%.4f%s", prefix, val, suffix);
    }
#endif
}

/* Reporte de seguridad formateado */
void cvqkd_print_security_report(const cvqkd_security_result_t *res) {
    if (!res) return;

    PRINTF("\r\n========================================================================\r\n");
    PRINTF("           EVALUACION DE SEGURIDAD CUANTICA EN CPU (HOLEVO BOUND)       \r\n");
    PRINTF("========================================================================\r\n");
    print_float_val("  * Transmitancia T:             ", res->T, "", 4);
    print_float_val("  (Atenuacion: ", res->loss_db, " dB", 2);
    print_float_val(" | Distancia: ", res->distance_km, " km)\r\n", 1);
    print_float_val("  * Ruido de Exceso (xi):        ", res->xi_snu, " SNU\r\n", 4);
    print_float_val("  * SNR Homodino:                ", res->snr_linear, "", 3);
    print_float_val(" (", res->snr_db, " dB)\r\n", 2);
    PRINTF("  ----------------------------------------------------------------------\r\n");
    print_float_val("  * Informacion Mutua I(A; B):   ", res->I_AB, " bits/simbolo", 4);
    print_float_val(" (beta real: ", res->beta_eff * 100.0, "%)\r\n", 1);
    print_float_val("  * Cota de Holevo chi(B; E):    ", res->chi_BE, " bits/simbolo (Max Eva)\r\n", 4);
    print_float_val("  * Tasa de Clave Asintotica:    ", res->K_asymp, " bits/simbolo", 4);
    print_float_val(" (", res->skr_asymp_mbps, " Mbps @ 1 Gbaud)\r\n", 2);
    print_float_val("  * Tasa Clave (Tamano Finito):  ", res->K_finite, " bits/simbolo", 4);
    print_float_val(" (", res->skr_finite_mbps, " Mbps)\r\n", 2);
    PRINTF("  * Bits tras Amplif. Privacidad: %u / 26112 bits ", res->pa_output_bits);
    print_float_val("(", res->pa_rate * 100.0, "%)\r\n", 1);
    PRINTF("  ----------------------------------------------------------------------\r\n");
    if (res->is_secure) {
        PRINTF("  >>> VEREDICTO DE SEGURIDAD:     [ PASS - SEGURO ]\r\n");
    } else {
        PRINTF("  >>> VEREDICTO DE SEGURIDAD:     [ ALERTA - INTRUSION / ABORT ]\r\n");
    }
    PRINTF("  >>> %s\r\n", res->status_msg);
    PRINTF("========================================================================\r\n\r\n");
}
