%% ========================================================================
%  SIMULACIÓN DE RECONCILIACIÓN INVERSA CV-QKD
%  Implementación del protocolo de reconciliación con códigos LDPC
%% ========================================================================
clear; clc; close all;

%% 0. PARÁMETROS FÍSICOS
% -------------------------------------------------------------------------
% Canal cuántico
L = 20;                             % Distancia de fibra (km)
alpha_dB = 0.2;                     % Atenuación de fibra (dB/km)
Va = 4;                             % Varianza de modulación de Alice (SNU)
T = 10^(-alpha_dB * L / 10);        % Transmitancia del canal

% Ruido
vel = 0.05;                         % Ruido electrónico (fracción del shot noise)
xi = 0.01;                          % Ruido de exceso a la entrada

% Tamaños de simulación
n = 26112;                          % Longitud del código LDPC
max_iter = 60;                      % Iteraciones máximas del decodificador
N_pulsos = 100000;                  % Número de pulsos a generar

%% 1. GENERACIÓN (ALICE)
% -------------------------------------------------------------------------
% Generación de cuadraturas aleatorias
q_Alice = sqrt(Va) * randn(N_pulsos, 1);
p_Alice = sqrt(Va) * randn(N_pulsos, 1);

% Vector intercalado (Q en posiciones impares, P en pares)
Xa = zeros(2 * N_pulsos, 1);
Xa(1:2:end) = q_Alice;
Xa(2:2:end) = p_Alice;

% Generación del ruido del canal
var_noise = 1 + vel + T * xi;       % Varianza total del ruido
std_noise = sqrt(var_noise);
z_noise_q = std_noise * randn(N_pulsos, 1);
z_noise_p = std_noise * randn(N_pulsos, 1);

%% 2. RECEPCIÓN (BOB)
% -------------------------------------------------------------------------
% Señales recibidas (canal con atenuación + ruido)
q_Bob = sqrt(T) * q_Alice + z_noise_q;
p_Bob = sqrt(T) * p_Alice + z_noise_p;

% Vector intercalado de Bob
Yb = zeros(2 * N_pulsos, 1);
Yb(1:2:end) = q_Bob;
Yb(2:2:end) = p_Bob;

% Cálculo de SNR
SNR_lineal = (T * Va) / var_noise;
SNR_dB = 10 * log10(SNR_lineal);
fprintf('SNR = %.2f dB\n', SNR_dB);

% Visualización del diagrama de fase
figure;
plot(q_Alice(1:1000), p_Alice(1:1000), 'bo', 'MarkerSize', 2); hold on;
plot(q_Bob(1:1000), p_Bob(1:1000), 'r.', 'MarkerSize', 4);
legend('Alice (Enviado)', 'Bob (Recibido)');
title(sprintf('Diagrama de Fase (Q vs P) @ %d km', L));
xlabel('Cuadratura Q'); ylabel('Cuadratura P');
axis square; grid on;

%% 3. GENERACIÓN DE MATRIZ H (LDPC 5G NR)
% -------------------------------------------------------------------------
% Cargar Base Graph 1 del estándar 5G NR-LDPC
Z = 384;                            % Factor de lifting
baseGraphFile = 'LDPC/NR-LDPC-BG-master/NR-LDPC-BG-master/NR_1_1_384.txt';

% Leer la matriz base desde archivo
BaseGraph = load(baseGraphFile);
[mb, nb] = size(BaseGraph);         % BG1: 46×68

% Dimensiones finales de H
M = mb * Z;                         % 17,664 filas (ecuaciones de paridad)
N_ldpc = nb * Z;                    % 26,112 columnas (bits totales)

fprintf('Matriz Base: %d×%d, Z=%d → H: %d×%d\n', mb, nb, Z, M, N_ldpc);

% Expansión de la matriz (lifting) usando matrices sparse
% Pre-calcular número de elementos no nulos para eficiencia
num_nonzero_blocks = sum(BaseGraph(:) >= 0);
nnz_total = num_nonzero_blocks * Z;

% Pre-asignar arrays para construcción sparse eficiente
row_indices = zeros(nnz_total, 1);
col_indices = zeros(nnz_total, 1);
values = ones(nnz_total, 1);

idx = 1;
for i = 1:mb
    for j = 1:nb
        shift_val = BaseGraph(i, j);
        if shift_val >= 0
            % Índices de la submatriz identidad rotada
            row_base = (i-1) * Z;
            col_base = (j-1) * Z;
            
            % Generar índices de la identidad circulante
            for k = 1:Z
                row_indices(idx) = row_base + k;
                col_indices(idx) = col_base + mod(k - 1 + shift_val, Z) + 1;
                idx = idx + 1;
            end
        end
    end
end

% Construir matriz sparse
H = sparse(row_indices, col_indices, values, M, N_ldpc);

fprintf('Matriz H generada: %d elementos no nulos (densidad: %.4f%%)\n', ...
    nnz(H), 100*nnz(H)/(M*N_ldpc));

%% 4. ESTIMACIÓN DE PARÁMETROS DEL CANAL
% -------------------------------------------------------------------------
% Separación de datos para reconciliación y estimación
Xr = Xa(1:2:2*n);                   % Reconciliación (posiciones impares)
Xp = Xa(2:2:2*n);                   % Estimación (posiciones pares)
Yr = Yb(1:2:2*n);
Yp = Yb(2:2:2*n);

% Estimación de transmitancia
Cov_xy = cov(Xp, Yp);
covarianza_xy = Cov_xy(1, 2);
varianza_x = var(Xp);
T_estimada = (covarianza_xy / varianza_x)^2;

% Estimación del ruido residual
sigma2 = var(Yp - sqrt(T_estimada) * Xp);
z_est = (sigma2 - 1 - vel) / T_estimada;

fprintf('T real = %.4f, T estimada = %.4f\n', T, T_estimada);

%% 5. CÁLCULO DEL SÍNDROME
% -------------------------------------------------------------------------
% Cuantización de las medidas de Bob
Kb = double(Yr <= 0);               % 1 si Yr <= 0, 0 en otro caso
S = mod(H * Kb, 2);                 % Síndrome

%% 6. RECONCILIACIÓN INVERSA (Min-Sum)
% -------------------------------------------------------------------------
% 6.1 Inicialización
LLR = sqrt(T_estimada) * Xr + z_est;
L = LLR;
Q = H .* L';                        % Proyección sobre las columnas de H

% Visualización de la matriz sparse
figure;
spy(Q);
title('Estructura de la matriz Q');

% 6.2 Búsqueda de mínimos por Check-Node
[filas_H, ~, ~] = find(H);
num_edges = length(filas_H);

[filaQ, columnaQ, val] = find(Q);
val_abs = abs(val);

% Ordenar por fila y valor absoluto
[~, sort_idx] = sortrows([filaQ, val_abs], [1 2]);
filas_sorted = filaQ(sort_idx);
cols_sorted = columnaQ(sort_idx);
val_abs_sorted = val_abs(sort_idx);

% Encontrar los dos mínimos por fila
[unique_filas, primer_idx] = unique(filas_sorted, 'first');
min1_vals = zeros(M, 1);
min1_cols = zeros(M, 1);
min2_vals = zeros(M, 1);

min1_vals(unique_filas) = val_abs_sorted(primer_idx);
min1_cols(unique_filas) = cols_sorted(primer_idx);
min2_vals(unique_filas) = val_abs_sorted(primer_idx + 1);

% 6.3 Cálculo de magnitudes de R (Min-Sum escalado)
alpha_ms = 0.75;                    % Factor de escala Min-Sum

vals_min1_expanded = min1_vals(filaQ);
vals_min2_expanded = min2_vals(filaQ);
cols_min1_expanded = min1_cols(filaQ);

% Selección: usar min2 si la columna actual tenía el min1
is_min_col = (columnaQ == cols_min1_expanded);

R_mags = zeros(num_edges, 1);
R_mags(~is_min_col) = vals_min1_expanded(~is_min_col);
R_mags(is_min_col) = vals_min2_expanded(is_min_col);
R_mags = R_mags * alpha_ms;

% 6.4 Cálculo de signos
[rows, cols] = find(H);
vals_Q = Q(sub2ind(size(Q), rows, cols));
signs_Q = sign(vals_Q);
signs_Q(signs_Q == 0) = 1;

% Paridad de signos negativos por fila
is_negative_sparse = sparse(rows, cols, double(signs_Q < 0), M, N_ldpc);
num_negatives_per_row = full(sum(is_negative_sparse, 2));
row_parity_signs = (-1) .^ num_negatives_per_row;

% Aplicar síndrome
syndrome_adjustment = (-1) .^ S;
global_row_signs = row_parity_signs .* syndrome_adjustment;
signs_expanded = global_row_signs(rows);
final_signs = signs_expanded .* signs_Q;

% Resultado final
R = final_signs .* R_mags;

fprintf('Reconciliación completada. Tamaño de R: %d elementos\n', length(R));