#include "cvqkd_security.h"
#include <stdio.h>

int main(void) {
    printf("========================================================\n");
    printf("   TEST DE VALIDACION MATEMATICA: SEGURIDAD CUANTICA    \n");
    printf("========================================================\n");

    cvqkd_security_params_t params;
    cvqkd_security_init_defaults(&params);

    cvqkd_security_result_t res;

    /* Caso 1: Canal nominal (10 km, T = 0.631, xi = 0.010 SNU), heterodino */
    /* t^2 = T*eta/2 = 0.1893 (Q16.16: 0x3075) */
    /* Var_B = 1 + v_el + t^2*(V_A + xi) = 2.0483 SNU -> sigma_sq = 20483 */
    int32_t T_hw_nom = 0x00003075;
    int32_t sigma_sq_nom = 20483;
    printf("\n--- CASO 1: CANAL NOMINAL (10 km, xi = 0.010 SNU) ---\n");
    cvqkd_evaluate_frame_security(&params, T_hw_nom, sigma_sq_nom, &res);
    cvqkd_print_security_report(&res);

    /* Caso 2: Estimación hardware de los vectores de MATLAB (expected_llr_math.txt) */
    int32_t T_hw_matlab = 0x00002F72;
    int32_t sigma_sq_matlab = 0x00004ECA;
    printf("\n--- CASO 2: VECTORES MATLAB (T = 0x2F72, sigma^2 = 0x4ECA) ---\n");
    cvqkd_evaluate_frame_security(&params, T_hw_matlab, sigma_sq_matlab, &res);
    cvqkd_print_security_report(&res);

    /* Caso 3: Ataque de interceptación y reenvío de Eva (ruido elevado sigma_sq = 45000) */
    int32_t sigma_sq_attack = 45000;
    printf("\n--- CASO 3: ATAQUE DE EVA / INTRUSION MASIVA (sigma^2 = %d) ---\n", sigma_sq_attack);
    cvqkd_evaluate_frame_security(&params, T_hw_nom, sigma_sq_attack, &res);
    cvqkd_print_security_report(&res);

    return 0;
}
