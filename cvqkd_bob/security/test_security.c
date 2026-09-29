#include "cvqkd_security.h"
#include <stdio.h>

int main(void) {
    printf("========================================================\n");
    printf("   TEST DE VALIDACION MATEMATICA: SEGURIDAD CUANTICA    \n");
    printf("========================================================\n");

    cvqkd_security_params_t params;
    cvqkd_security_init_defaults(&params);

    cvqkd_security_result_t res;

    /* Caso 1: Canal nominal seguro (L = 25 km, xi = 0.010 SNU) */
    /* T_eta = 0.1900 (Q16.16: 0x30A3) -> T = 0.3162 */
    /* Var_B = 0.1900*4 + 1.05 + 0.1900*0.010 = 1.8119 SNU -> sigma_sq = 18119 */
    int32_t T_hw_nom = 0x000030A3;
    int32_t sigma_sq_nom = 18119;
    printf("\n--- CASO 1: CANAL NOMINAL OPTICO SEGURO (L = 25 km, xi = 0.010 SNU) ---\n");
    cvqkd_evaluate_frame_security(&params, T_hw_nom, sigma_sq_nom, &res);
    cvqkd_print_security_report(&res);

    /* Caso 2: Canal medido con vectores de MATLAB (T = 0x4424, sigma^2 = 0x5595) */
    int32_t T_hw_matlab = 0x00004424;
    int32_t sigma_sq_matlab = 0x00005595;
    printf("\n--- CASO 2: VECTORES MATLAB HARDWARE (T = 0x4424, sigma^2 = 0x5595) ---\n");
    cvqkd_evaluate_frame_security(&params, T_hw_matlab, sigma_sq_matlab, &res);
    cvqkd_print_security_report(&res);

    /* Caso 3: Ataque de interceptación y reenvío de Eva (ruido elevado sigma_sq = 45000) */
    int32_t sigma_sq_attack = 45000;
    printf("\n--- CASO 3: ATAQUE DE EVA / INTRUSION MASIVA (sigma^2 = %d) ---\n", sigma_sq_attack);
    cvqkd_evaluate_frame_security(&params, T_hw_nom, sigma_sq_attack, &res);
    cvqkd_print_security_report(&res);

    return 0;
}
