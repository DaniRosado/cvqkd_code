%% ========================================================================
% GOLDEN MODEL: Estimador de Parámetros CV-QKD (Testbench de Hardware)
% ========================================================================
clear; clc;

N_sacrificio = 100;   % Muestras a procesar por el hardware
N_bob_total  = 200;   % Tamaño de la memoria Ping-Pong de Bob para el test

disp('--- GENERANDO VECTORES DE TEST PARA VIVADO ---');

% 1. Generar datos enteros aleatorios de 16 bits para Bob
Q_B_full = randi([-32768, 32767], N_bob_total, 1, 'int16');
P_B_full = randi([-32768, 32767], N_bob_total, 1, 'int16');

% 2. Generar 100 punteros aleatorios sin repetición (0 a N_bob_total-1)
punteros = randperm(N_bob_total, N_sacrificio)' - 1;

% 3. Extraer los datos de sacrificio de Bob (Los que coinciden con los punteros)
% En MATLAB los índices empiezan en 1, por eso sumamos 1
Q_B_sac = Q_B_full(punteros + 1);
P_B_sac = P_B_full(punteros + 1);

% 4. Generar datos de Alice (solo las 100 muestras sacrificadas)
Q_A_sac = randi([-32768, 32767], N_sacrificio, 1, 'int16');
P_A_sac = randi([-32768, 32767], N_sacrificio, 1, 'int16');

% ========================================================================
% 5. CÁLCULO DE ACUMULADORES EXACTOS (Usando 64 bits para evitar overflow)
% ========================================================================
sum_P_B = sum(int64(P_B_sac));
sum_Q_B = sum(int64(Q_B_sac));
sum_P_A = sum(int64(P_A_sac));
sum_Q_A = sum(int64(Q_A_sac));

sum_sq_P_B = sum(int64(P_B_sac).^2);
sum_sq_Q_B = sum(int64(Q_B_sac).^2);

sum_cov_P = sum(int64(P_A_sac) .* int64(P_B_sac));
sum_cov_Q = sum(int64(Q_A_sac) .* int64(Q_B_sac));

% ========================================================================
% 6. EXPORTACIÓN A ARCHIVOS .TXT PARA VIVADO
% ========================================================================
% A) Pointer RAM (Direcciones)
fid_ptr = fopen('ptr_ram.txt', 'w');
for i = 1:N_sacrificio
    fprintf(fid_ptr, '%04X\n', punteros(i));
end
fclose(fid_ptr);

% B) BRAM de Bob {Q_B, P_B} empaquetados en 32 bits
fid_bob = fopen('bob_ram.txt', 'w');
for i = 1:N_bob_total
    q_hex = typecast(Q_B_full(i), 'uint16');
    p_hex = typecast(P_B_full(i), 'uint16');
    fprintf(fid_bob, '%04X%04X\n', q_hex, p_hex);
end
fclose(fid_bob);

% C) BRAM de Alice {Q_A, P_A} empaquetados en 32 bits
fid_alice = fopen('alice_ram.txt', 'w');
for i = 1:N_sacrificio
    q_hex = typecast(Q_A_sac(i), 'uint16');
    p_hex = typecast(P_A_sac(i), 'uint16');
    fprintf(fid_alice, '%04X%04X\n', q_hex, p_hex);
end
fclose(fid_alice);

% D) Resultados Esperados (Golden Model)
fid_exp = fopen('expected_results.txt', 'w');
% Escribimos los 8 valores de 64 bits (16 caracteres hexadecimales)
fprintf(fid_exp, '%016X\n', typecast(int64(sum_sq_P_B), 'uint64'));
fprintf(fid_exp, '%016X\n', typecast(int64(sum_P_B),    'uint64'));
fprintf(fid_exp, '%016X\n', typecast(int64(sum_cov_P),  'uint64'));
fprintf(fid_exp, '%016X\n', typecast(int64(sum_P_A),    'uint64'));
fprintf(fid_exp, '%016X\n', typecast(int64(sum_sq_Q_B), 'uint64'));
fprintf(fid_exp, '%016X\n', typecast(int64(sum_Q_B),    'uint64'));
fprintf(fid_exp, '%016X\n', typecast(int64(sum_cov_Q),  'uint64'));
fprintf(fid_exp, '%016X\n', typecast(int64(sum_Q_A),    'uint64'));
fclose(fid_exp);

disp('Archivos guardados correctamente.');