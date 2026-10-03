/*
 * Test del módulo de seguridad (se compila en el PC con gcc, ver run_tests.sh).
 * Comprueba el veredicto en los casos de referencia del punto de trabajo
 * (10 km, T = 0.631, xi = 0.010 SNU, heterodino):
 *   - una trama aislada siempre se aborta (tamaño finito);
 *   - un bloque de 1000 tramas con el canal nominal da clave;
 *   - el mismo bloque con un 1 % de tramas atacadas (xi = 2 SNU) se aborta.
 */
#include "cvqkd_security.h"
#include <stdio.h>

static int failures = 0;

static void check(const char *name, const cvqkd_security_params_t *p,
                  int32_t T_q16, int32_t sigma_sq, bool expect_secure)
{
    cvqkd_security_result_t res;
    cvqkd_evaluate_frame_security(p, T_q16, sigma_sq, &res);
    printf("\n--- %s ---\n", name);
    cvqkd_print_security_report(&res);
    if (res.is_secure != expect_secure) {
        printf("  [FAIL] veredicto %s, se esperaba %s\n",
               res.is_secure ? "PASS" : "ABORT", expect_secure ? "PASS" : "ABORT");
        failures++;
    }
}

int main(void)
{
    cvqkd_security_params_t frame;
    cvqkd_security_init_defaults(&frame);

    cvqkd_security_params_t block = frame;   /* Bloque de 1000 tramas */
    block.m_samples    *= 1000;
    block.n_key_bits   *= 1000;
    block.leak_ec_bits *= 1000;

    /* t^2 = T*eta/2 = 0.1893 (Q16.16: 0x3075); Var_B = 1 + v_el + t^2*(V_A + xi) = 2.0483 SNU */
    const int32_t T_nom = 0x3075, var_nom = 20483;
    /* 10 de 1000 tramas con xi = 2 SNU: +t^2 * 2 * N0 * 10/1000 = +38 cuentas de media */
    const int32_t var_attack = var_nom + 38;

    check("Trama aislada, canal nominal", &frame, T_nom, var_nom, false);
    check("Trama aislada de MATLAB (T = 0x2F72, sigma^2 = 0x4ECA)", &frame, 0x2F72, 0x4ECA, false);
    check("Trama aislada con ataque masivo (sigma^2 = 45000)", &frame, T_nom, 45000, false);
    check("Bloque de 1000 tramas, canal nominal", &block, T_nom, var_nom, true);
    check("Bloque de 1000 tramas con 10 tramas atacadas", &block, T_nom, var_attack, false);

    printf("\nRESULTADO: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures != 0;
}
