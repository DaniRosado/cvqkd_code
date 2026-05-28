%% DEBUG_FIXED_POINT - Diagnóstico detallado de estimación de parámetros
%
% Compara paso a paso el cálculo de parámetros en punto fijo

clear; clc;

fprintf('========================================\n');
fprintf(' Debug: Estimación de Parámetros (Fixed-Point)\n');
fprintf('========================================\n\n');

% Cargar datos de la última simulación
DATA_DIR = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'data');

% Buscar archivos de Bob RAM con muestras de sacrificio
% Asumiendo que el script principal los guardó
fprintf('[1/3] Cargando datos de sacrificio...\n');

% Generar datos sintéticos similares a la simulación real
N_samples = 1000;
VarA_adc = 10000;  % Varianza de Alice en unidades ADC

% Simular mediciones correlacionadas
rng(42);  % Seed fijo para reproducibilidad
P_alice = int16(randn(N_samples, 1) * sqrt(VarA_adc));
Q_alice = int16(randn(N_samples, 1) * sqrt(VarA_adc));

% Bob recibe con atenuación T*eta ≈ 0.5 y ruido
T_eta = 0.5;
noise_var = VarA_adc * (1 - T_eta);
P_bob = int16(double(P_alice) * sqrt(T_eta) + randn(N_samples, 1) * sqrt(noise_var));
Q_bob = int16(double(Q_alice) * sqrt(T_eta) + randn(N_samples, 1) * sqrt(noise_var));

fprintf('  N_samples = %d\n', N_samples);
fprintf('  VarA_adc = %d\n', VarA_adc);
fprintf('  T*eta simulado = %.4f\n\n', T_eta);

%% Cálculo flotante (referencia)
fprintf('[2/3] Calculando parámetros flotantes (referencia)...\n');

var_B_float = (var(double(P_bob), 1) + var(double(Q_bob), 1)) / 2;
cov_PA_PB = cov(double(P_alice), double(P_bob));
cov_QA_QB = cov(double(Q_alice), double(Q_bob));
cov_AB_float = (cov_PA_PB(1,2) + cov_QA_QB(1,2)) / 2;
T_eta_float = cov_AB_float / VarA_adc;
sigma_float = sqrt(var_B_float);

fprintf('  var_B (float)    = %.2f\n', var_B_float);
fprintf('  cov_AB (float)   = %.2f\n', cov_AB_float);
fprintf('  T*eta (float)    = %.4f\n', T_eta_float);
fprintf('  Sigma (float)    = %.2f\n\n', sigma_float);

%% Cálculo punto fijo (emulación FPGA)
fprintf('[3/3] Calculando parámetros punto fijo (emulación FPGA)...\n');

% Acumuladores de 64 bits
sum_P_B = sum(int64(P_bob));
sum_Q_B = sum(int64(Q_bob));
sum_P_A = sum(int64(P_alice));
sum_Q_A = sum(int64(Q_alice));

sum_sq_P_B = sum(int64(P_bob).^2);
sum_sq_Q_B = sum(int64(Q_bob).^2);
sum_cov_P = sum(int64(P_alice) .* int64(P_bob));
sum_cov_Q = sum(int64(Q_alice) .* int64(Q_bob));

fprintf('  sum_P_B = %d\n', sum_P_B);
fprintf('  sum_sq_P_B = %d\n', sum_sq_P_B);
fprintf('  sum_cov_P = %d\n\n', sum_cov_P);

% Constante de división: 2^45 / ((N/2)^2)
N_int = int64(N_samples);
INV_2N2_shift = 45;
INV_2N2 = int64(round(2^INV_2N2_shift / ((N_samples/2)^2)));

fprintf('  INV_2N2 (2^45 / (N/2)^2) = %d\n', INV_2N2);
fprintf('  Como double: %.12e\n\n', double(INV_2N2));

% Numeradores de covarianza y varianza
cross_P_AB = int64(sum_P_A) * int64(sum_P_B);
cross_Q_AB = int64(sum_Q_A) * int64(sum_Q_B);
sum_cov_total = int64(sum_cov_P) + int64(sum_cov_Q);
num_cov_AB = (N_int * sum_cov_total) - (cross_P_AB + cross_Q_AB);

sq_sum_P_B = int64(sum_P_B) * int64(sum_P_B);
sq_sum_Q_B = int64(sum_Q_B) * int64(sum_Q_B);
sum_sq_total = int64(sum_sq_P_B) + int64(sum_sq_Q_B);
num_var_B = (N_int * sum_sq_total) - (sq_sum_P_B + sq_sum_Q_B);

fprintf('  num_cov_AB = %d\n', num_cov_AB);
fprintf('  num_var_B = %d\n\n', num_var_B);

% División mediante multiplicación y shift (método FPGA)
fprintf('  Método FPGA: multiply-and-shift\n');

% Convertir a uint64 para la multiplicación
prod_cov = uint64(num_cov_AB) * uint64(INV_2N2);
prod_var = uint64(num_var_B) * uint64(INV_2N2);

fprintf('  num_cov_AB * INV_2N2 = %s (uint64)\n', num2str(prod_cov));
fprintf('  num_var_B * INV_2N2  = %s (uint64)\n\n', num2str(prod_var));

% Shift de 48 bits
cov_AB_pure = bitshift(typecast(prod_cov, 'int64'), -48);
var_B_pure = bitshift(typecast(prod_var, 'int64'), -48);

fprintf('  Después de >>48:\n');
fprintf('  cov_AB_pure = %d\n', cov_AB_pure);
fprintf('  var_B_pure  = %d\n\n', var_B_pure);

% Calcular Sigma
Sigma_raw_cordic = floor(sqrt(max(double(var_B_pure), 0)));
Sigma_fp = int64(double(Sigma_raw_cordic) * 65536.0);

fprintf('  Sigma (integer) = %.2f\n', Sigma_raw_cordic);
fprintf('  Sigma (Q16.16)  = %d\n', Sigma_fp);
fprintf('  Sigma (convertido) = %.2f\n\n', double(Sigma_fp) / 65536.0);

%% Comparación
fprintf('========================================\n');
fprintf(' COMPARACIÓN\n');
fprintf('========================================\n');
fprintf('Parámetro         | Flotante  | Punto Fijo | Error\n');
fprintf('------------------+-----------+------------+--------\n');
fprintf('var_B             | %9.2f | %10.2f | %6.2f\n', var_B_float, double(var_B_pure), abs(var_B_float - double(var_B_pure)));
fprintf('Sigma             | %9.2f | %10.2f | %6.2f\n', sigma_float, double(Sigma_fp)/65536, abs(sigma_float - double(Sigma_fp)/65536));
fprintf('========================================\n\n');

if abs(sigma_float - double(Sigma_fp)/65536) < 1.0
    fprintf('[✓] Estimación punto fijo CORRECTA\n');
else
    fprintf('[✗] Estimación punto fijo INCORRECTA\n');
    fprintf('    Diferencia de Sigma: %.2f (debería ser < 1.0)\n', abs(sigma_float - double(Sigma_fp)/65536));
end
