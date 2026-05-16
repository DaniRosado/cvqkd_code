%% GOLDEN MODEL: Estimador de Parámetros Finales (Solución Híbrida Fraction-Free)
clear; clc;

N_sacrificio = 26112;
N_bob_total  = 52224;

disp('--- GENERANDO 26.112 MUESTRAS PARA VIVADO (Puede tardar unos segundos) ---');

% 1. Generar datos aleatorios y punteros
Q_B_full = randi([-32768, 32767], N_bob_total, 1, 'int16');
P_B_full = randi([-32768, 32767], N_bob_total, 1, 'int16');
punteros = randperm(N_bob_total, N_sacrificio)' - 1;

Q_B_sac = Q_B_full(punteros + 1); 
P_B_sac = P_B_full(punteros + 1);
Q_A_sac = randi([-32768, 32767], N_sacrificio, 1, 'int16');
P_A_sac = randi([-32768, 32767], N_sacrificio, 1, 'int16');

% 2. Acumuladores Básicos de 64 bits (Salida de los MACs)
sum_P_B = sum(int64(P_B_sac)); sum_sq_P_B = sum(int64(P_B_sac).^2);
sum_Q_B = sum(int64(Q_B_sac)); sum_sq_Q_B = sum(int64(Q_B_sac).^2);
sum_P_A = sum(int64(P_A_sac)); sum_cov_P  = sum(int64(P_A_sac) .* int64(P_B_sac));
sum_Q_A = sum(int64(Q_A_sac)); sum_cov_Q  = sum(int64(Q_A_sac) .* int64(Q_B_sac));

% =========================================================================
% 3. EMULANDO LA FPGA EXACTAMENTE (Solución Fraction-Free)
% =========================================================================
N_SAMPLES = int64(26112);
INV_2N2   = int64(206409); % 2^48 / (2 * 26112^2)

% Etapa 1: Productos cruzados
cross_P_AB = sum_P_A * sum_P_B;
cross_Q_AB = sum_Q_A * sum_Q_B;
sq_sum_P_B = sum_P_B * sum_P_B;
sq_sum_Q_B = sum_Q_B * sum_Q_B;

% Etapa 2: Numeradores Gigantes (Precisión Infinita)
num_cov_AB = (N_SAMPLES * (sum_cov_P + sum_cov_Q)) - (cross_P_AB + cross_Q_AB);
num_var_B  = (N_SAMPLES * (sum_sq_P_B + sum_sq_Q_B)) - (sq_sum_P_B + sq_sum_Q_B);

% Etapa 3: Recuperación de la escala Q16.16 (>>> 48)
% Truco de Verificación: Multiplicamos forzando wrap-around de 64 bits (como hace Vivado) 
% y luego hacemos el desplazamiento aritmético (con signo).
temp_cov = typecast(uint64(num_cov_AB) .* uint64(INV_2N2), 'int64');
cov_AB_pure = bitshift(temp_cov, -48); 

temp_var = typecast(uint64(num_var_B) .* uint64(INV_2N2), 'int64');
var_B_pure = bitshift(temp_var, -48);

% Parámetros de Calibración
calib_N0    = 10000;
calib_Velec = 1000;
calib_VarA  = 40000;

% Etapa 4: División IP y Resta Final
% El divisor de Vivado en Q16.16 equivale a multiplicar el numerador por 2^16
T_expected  = bitshift(cov_AB_pure * 65536, 0) / calib_VarA; 
xi_expected = var_B_pure - calib_Velec - calib_N0 - calib_VarA;

% =========================================================================
% 4. EXPORTACIÓN DE VALORES INTERMEDIOS (PARA DEPURACIÓN EN VIVADO)
% =========================================================================
fid_debug = fopen('matlab_debug_accumulators.txt', 'w');
fprintf(fid_debug, '--- VALORES DE LOS MACs ---\n');
fprintf(fid_debug, 'Sum_P_A:      %016X\n', typecast(sum_P_A, 'uint64'));
fprintf(fid_debug, 'Sum_P_B:      %016X\n', typecast(sum_P_B, 'uint64'));
fprintf(fid_debug, 'SumCov_P:     %016X\n', typecast(sum_cov_P, 'uint64'));
fprintf(fid_debug, '\n--- ETAPA 1 y 2 (PIPELINE INTERNO) ---\n');
fprintf(fid_debug, 'Cross_P_AB:   %016X\n', typecast(cross_P_AB, 'uint64'));
fprintf(fid_debug, 'Num_Cov_AB:   %016X\n', typecast(num_cov_AB, 'uint64'));
fprintf(fid_debug, '\n--- ETAPA 3 (PREVIO A DIVISIÓN) ---\n');
% Aquí guardamos en 32 bits (8 caracteres Hex)
fprintf(fid_debug, 'Cov_AB_pure:  %08X\n', typecast(int32(cov_AB_pure), 'uint32'));
fprintf(fid_debug, 'Var_B_pure:   %08X\n', typecast(int32(var_B_pure), 'uint32'));
fclose(fid_debug);

% 5. Exportación de RAMs y Resultados Finales
fid_ptr = fopen('ptr_ram.txt', 'w');
for i=1:N_sacrificio, fprintf(fid_ptr, '%04X\n', punteros(i)); end; fclose(fid_ptr);

fid_bob = fopen('bob_ram.txt', 'w');
for i=1:N_bob_total, fprintf(fid_bob, '%04X%04X\n', typecast(Q_B_full(i), 'uint16'), typecast(P_B_full(i), 'uint16')); end; fclose(fid_bob);

fid_alice = fopen('alice_ram.txt', 'w');
for i=1:N_sacrificio, fprintf(fid_alice, '%04X%04X\n', typecast(Q_A_sac(i), 'uint16'), typecast(P_A_sac(i), 'uint16')); end; fclose(fid_alice);

fid_exp = fopen('expected_results.txt', 'w');
fprintf(fid_exp, '%08X\n', typecast(int32(T_expected), 'uint32'));
fprintf(fid_exp, '%08X\n', typecast(int32(xi_expected), 'uint32'));
fclose(fid_exp);

disp('¡Archivos de simulación y depuración actualizados!');