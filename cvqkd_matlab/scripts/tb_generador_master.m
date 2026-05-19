%% ========================================================================
%  MASTER TESTBENCH: END-TO-END CV-QKD (Láser -> Fibra -> DSP -> Math)
% ========================================================================
clear; clc; close all;

%% 0. RUTAS DEL PROYECTO (ajusta si mueves el script)
SCRIPT_DIR = fileparts(mfilename('fullpath'));
if isempty(SCRIPT_DIR), SCRIPT_DIR = pwd(); end
addpath(SCRIPT_DIR);
DATA_DIR   = fullfile(SCRIPT_DIR, '..', 'data');
BOB_DIR    = fullfile(SCRIPT_DIR, '..', '..', 'cvqkd_bob');
ALICE_DATA_DIR = fullfile(SCRIPT_DIR, '..', '..', 'cvqkd_alice', 'data');
ALICE_SIM_DIR  = fullfile(SCRIPT_DIR, '..', '..', 'cvqkd_alice', 'sim');

%% 0. RUTAS DEL PROYECTO (ajusta si mueves el script)
SCRIPT_DIR = fileparts(mfilename('fullpath'));
DATA_DIR   = fullfile(SCRIPT_DIR, '..', 'data');
BOB_DIR    = fullfile(SCRIPT_DIR, '..', '..', 'cvqkd_bob');

%% 1. PARÁMETROS DEL SISTEMA
ENABLE_EXPORT_VIVADO = trueGenial;

% --- Parámetros de Trama y Memoria ---
L_trama     = 16;      % 1 Piloto + 15 Datos
N_BOB_DATA  = 26112;   % Datos útiles que caben en la RAM de Bob -> genero el doble para poder sacrificar
N_FRAMES    = ceil(N_BOB_DATA / 15); % ~1741 tramas
N_SAMPLES   = N_BOB_DATA/2;   % Datos sacrificados para la estimación

% En la fibra viajan los datos + los pilotos. Sumamos 1 piloto final para interpolar
N_FIBER     = N_FRAMES * L_trama + 1; 

% --- Parámetros Físicos del Canal ---
Ts           = 1e-9;   % Tiempo de símbolo (1 Gbaud)
T_real       = 0.8;    % Transmitancia real de la fibra
xi_real      = 0.01;   % Ruido en exceso cuántico (SNU)
V_A_snu      = 8.0;  % Varianza de Alice (SNU)
env_va = getenv('VA_SNU');
if ~isempty(env_va)
    V_A_snu = str2double(env_va);
end
V_elec_snu   = 0.1;    % Ruido electrónico (SNU)
eta_detector = 0.6;    % Eficiencia del fotodiodo

% --- Calibración del Hardware (ADC) ---
N0_adc_var   = 10000;  % Varianza para 1 SNU
Amp_Piloto   = 20000;  % Amplitud fuerte para el pulso piloto (para no perder fase)

%% 2. MODELO DE RUIDO DE FASE DEL CANAL (Tu código integrado)
disp('1. Generando Perfil de Ruido de Fase (Wiener + Acústico)...');
t = (0:N_FIBER-1)' * Ts;

% A) Proceso de Wiener (Ancho de línea del láser 100 kHz)
sigma_w = sqrt(2 * pi * 100e3 * Ts); 
ruido_wiener = sigma_w * randn(N_FIBER, 1);
fase_wiener = cumsum(ruido_wiener);  

% B) Ruido Acústico (500 Hz)
f_acustica = 500; 
A_acustica = 0.5; 
fase_acustica = A_acustica * sin(2 * pi * f_acustica * t);

% C) Deriva Total
fase_total_canal = fase_wiener + fase_acustica;

%% 3. ALICE: GENERACIÓN CUÁNTICA CON PILOTOS INTERCALADOS
disp('2. Alice transmitiendo (Datos + Pilotos)...');
VarA_adc = V_A_snu * N0_adc_var;

P_A_tx = zeros(N_FIBER, 1);
Q_A_tx = zeros(N_FIBER, 1);

idx_pilotos = 1:L_trama:N_FIBER;
idx_datos   = setdiff(1:N_FIBER, idx_pilotos);

% Alice genera ruido Gaussiano para los datos
P_A_tx(idx_datos) = sqrt(VarA_adc) * randn(length(idx_datos), 1);
Q_A_tx(idx_datos) = sqrt(VarA_adc) * randn(length(idx_datos), 1);

% Alice inserta los pilotos fuertes en la cuadratura P (Fase 0)
P_A_tx(idx_pilotos) = Amp_Piloto;
Q_A_tx(idx_pilotos) = 0;

%% 4. EL CANAL: ATENUACIÓN Y AWGN
disp('3. La fibra atenúa e inyecta AWGN...');
Ruido_Total_snu = 1.0 + V_elec_snu + (T_real * eta_detector * xi_real);
Ruido_Total_adc = Ruido_Total_snu * N0_adc_var;

Z_noise_P = sqrt(Ruido_Total_adc) * randn(N_FIBER, 1);
Z_noise_Q = sqrt(Ruido_Total_adc) * randn(N_FIBER, 1);

% Rotación de Fase + Atenuación + AWGN
P_rx_ideal = sqrt(T_real * eta_detector) * P_A_tx;
Q_rx_ideal = sqrt(T_real * eta_detector) * Q_A_tx;

P_B_rx = P_rx_ideal .* cos(fase_total_canal) - Q_rx_ideal .* sin(fase_total_canal) + Z_noise_P;
Q_B_rx = P_rx_ideal .* sin(fase_total_canal) + Q_rx_ideal .* cos(fase_total_canal) + Z_noise_Q;

%% 5. RECEPCIÓN Y DSP DE BOB (Recuperación de Fase Vectorizada)
disp('4. DSP de Bob: Siguiendo y deshaciendo la fase (Unwrap)...');

% 1. Extracción de los pilotos recibidos y cálculo de su fase cruda
P_pilotos_rx = P_B_rx(idx_pilotos);
Q_pilotos_rx = Q_B_rx(idx_pilotos);

fase_pilotos_raw = atan2(Q_pilotos_rx, P_pilotos_rx);

% 2. EL SECRETO: Desenrollar la fase para evitar saltos de 2*pi
fase_pilotos_limpia = unwrap(fase_pilotos_raw);

% 3. Interpolación lineal para estimar la fase de todos los símbolos
% (interp1 interpola los huecos de los datos basándose en los pilotos YA desenrollados)
fase_estimada = interp1(idx_pilotos, fase_pilotos_limpia, (1:N_FIBER)', 'linear');
% wrapToPi is not available in Octave; inline the wrapping
fase_estimada = mod(fase_estimada + pi, 2*pi) - pi;
%fase_estimada_datos = fase_estimada(idx_datos);

% (Pequeño arreglo por si el último símbolo queda fuera de la interpolación)
fase_estimada(isnan(fase_estimada)) = fase_estimada(find(~isnan(fase_estimada), 1, 'last'));

% 4. Des-rotación de toda la trama a la vez (DSP Vectorizado)
P_B_rec_full = P_B_rx .* cos(-fase_estimada) - Q_B_rx .* sin(-fase_estimada);
Q_B_rec_full = P_B_rx .* sin(-fase_estimada) + Q_B_rx .* cos(-fase_estimada);

% 5. Extraemos solo los datos útiles (descartando los pilotos de la trama)
P_A_data = P_A_tx(idx_datos); 
Q_A_data = Q_A_tx(idx_datos);
P_B_rec  = P_B_rec_full(idx_datos);
Q_B_rec  = Q_B_rec_full(idx_datos);

% 6. Truncamos al tamaño exacto de la RAM de Bob
P_A_data = P_A_data(1:N_BOB_DATA);
Q_A_data = Q_A_data(1:N_BOB_DATA);
P_B_rec  = P_B_rec(1:N_BOB_DATA);
Q_B_rec  = Q_B_rec(1:N_BOB_DATA);

% Cuantizamos a 16 bits todo lo recuperado (Bob RAM) y lo original (Alice RAM)
P_A_int = int16(round(P_A_data)); Q_A_int = int16(round(Q_A_data));
P_B_int = int16(round(P_B_rec));  Q_B_int = int16(round(Q_B_rec));

%% 6. SELECCIÓN DE PUNTEROS Y ESTIMACIÓN FLOTANTE (MATLAB IDEAL)
disp('5. Seleccionando muestras de sacrificio y calculando métricas...');
punteros = sort(randperm(N_BOB_DATA, N_SAMPLES)') - 1;

% Máscara de sacrificio (1 = sacrificar, 0 = mantener)
mascara_sacrificio = zeros(N_BOB_DATA, 1);
mascara_sacrificio(punteros + 1) = 1;

% Sacamos las muestras correlacionadas usando los punteros
P_B_sac = P_B_int(punteros + 1); Q_B_sac = Q_B_int(punteros + 1);
P_A_sac = P_A_int(punteros + 1); Q_A_sac = Q_A_int(punteros + 1);

% Funciones nativas de MATLAB (Flotante)
var_B_float = (var(double(P_B_sac), 1) + var(double(Q_B_sac), 1)) / 2;
cov_mat_P = cov(double(P_A_sac), double(P_B_sac), 1);
cov_mat_Q = cov(double(Q_A_sac), double(Q_B_sac), 1);
cov_AB_float = (cov_mat_P(1,2) + cov_mat_Q(1,2)) / 2;

Sigma_Sq_ideal   = var_B_float;
Sigma_ideal      = sqrt(Sigma_Sq_ideal);
Sqrt_T_eta_ideal = cov_AB_float / VarA_adc;
T_eta_ideal = Sqrt_T_eta_ideal^2; % T * eta = (Cov / VarA)^2

%% 7. EMULACIÓN PUNTO FIJO (LLR_Math_Unit FPGA)
disp('6. Emulando el Hardware de Punto Fijo (FPGA)...');

sum_P_B = sum(int64(P_B_sac)); sum_sq_P_B = sum(int64(P_B_sac).^2);
sum_Q_B = sum(int64(Q_B_sac)); sum_sq_Q_B = sum(int64(Q_B_sac).^2);
sum_P_A = sum(int64(P_A_sac)); sum_cov_P  = sum(int64(P_A_sac) .* int64(P_B_sac));
sum_Q_A = sum(int64(Q_A_sac)); sum_cov_Q  = sum(int64(Q_A_sac) .* int64(Q_B_sac));

N_int = int64(N_SAMPLES); INV_2N2 = int64(round(2^45 / ((N_SAMPLES/2)^2)));
cross_P_AB = sum_P_A * sum_P_B; cross_Q_AB = sum_Q_A * sum_Q_B;
sq_sum_P_B = sum_P_B * sum_P_B; sq_sum_Q_B = sum_Q_B * sum_Q_B;

num_cov_AB = (N_int * (sum_cov_P + sum_cov_Q)) - (cross_P_AB + cross_Q_AB);
num_var_B  = (N_int * (sum_sq_P_B + sum_sq_Q_B)) - (sq_sum_P_B + sq_sum_Q_B);

if exist('OCTAVE_VERSION', 'builtin')
    num_cov_AB_d = double(num_cov_AB);
    num_var_B_d  = double(num_var_B);
    inv_2n2_d = double(INV_2N2);
    cov_AB_pure = int64(floor((num_cov_AB_d * inv_2n2_d) / 2^48));
    var_B_pure  = int64(floor((num_var_B_d  * inv_2n2_d) / 2^48));
else
    cov_AB_pure = bitshift(typecast(uint64(num_cov_AB) .* uint64(INV_2N2), 'int64'), -48);
    var_B_pure  = bitshift(typecast(uint64(num_var_B)  .* uint64(INV_2N2), 'int64'), -48);
end

Sigma_Sq_fp  = var_B_pure;
T_raw_15bits = bitshift(cov_AB_pure * 32768, 0) / int64(VarA_adc);
Sqrt_T_eta_fp = T_raw_15bits * 2;
T_eta_fp = bitshift(int64(Sqrt_T_eta_fp)^2, -16);

Sigma_raw_cordic = floor(sqrt(max(double(Sigma_Sq_fp), 0)));
Sigma_fp         = int64(double(Sigma_raw_cordic) * 65536.0);

%% 8. GRÁFICAS DEL GEMELO DIGITAL
figure('Name', 'End-to-End QKD Tracker', 'Position', [100, 100, 1200, 600]);

% Gráfica de Ruido de Fase (DSP vs Canal)
subplot(1, 2, 1);
plot(t * 1e6, fase_total_canal, 'r', 'LineWidth', 1.5); hold on;
plot(t * 1e6, fase_estimada, 'b--', 'LineWidth', 1.5);
title('Tracking de Fase del DSP de Bob');
xlabel('Tiempo (\mu s)'); ylabel('Fase (Radianes)');
legend('Ruido del Canal (Láser + Acústico)', 'Estimación DSP (Pilotos)');
grid on;

% Constelación de los datos recuperados (Primeros 1000)
subplot(1, 2, 2);
plot(P_A_data(1:1000), Q_A_data(1:1000), 'go', 'MarkerSize', 3); hold on;
plot(P_B_rec(1:1000), Q_B_rec(1:1000), 'bx', 'MarkerSize', 3);
title('Constelación (1000 Símbolos)');
xlabel('P (ADC)'); ylabel('Q (ADC)');
legend('TX Ideal (Alice)', 'RX Recuperado y Derrotado (Bob)');
grid on; axis equal;

%% 9. RECONCILIACIÓN MULTIDIMENSIONAL (8D) Y EXTRACCIÓN DE LLRs
disp('8. Simulando Mapeo Multidimensional (MDR 8D)...');

N_dimensiones = 8;
symbols_per_block = N_dimensiones / 2; % 4 simbolos complejos -> 8D
N_bloques = floor(N_BOB_DATA / symbols_per_block);

num_used = N_bloques * symbols_per_block;
P_A_mdr = double(P_A_data(1:num_used));
Q_A_mdr = double(Q_A_data(1:num_used));
P_B_mdr = double(P_B_rec(1:num_used));
Q_B_mdr = double(Q_B_rec(1:num_used));

X = zeros(N_dimensiones, N_bloques);
Y = zeros(N_dimensiones, N_bloques);
for blk = 1:N_bloques
    base = (blk-1) * symbols_per_block;
    X(:, blk) = [P_A_mdr(base+1); Q_A_mdr(base+1); P_A_mdr(base+2); Q_A_mdr(base+2); ...
                 P_A_mdr(base+3); Q_A_mdr(base+3); P_A_mdr(base+4); Q_A_mdr(base+4)];
    Y(:, blk) = [P_B_mdr(base+1); Q_B_mdr(base+1); P_B_mdr(base+2); Q_B_mdr(base+2); ...
                 P_B_mdr(base+3); Q_B_mdr(base+3); P_B_mdr(base+4); Q_B_mdr(base+4)];
end

bits_bob_all = randi([0 1], N_dimensiones, N_bloques);
LLR_all = zeros(N_dimensiones, N_bloques);

sigma_eff = double(Sigma_ideal);
inv_sigma2 = 2.0 / (sigma_eff * sigma_eff + eps);

for blk = 1:N_bloques
    % --- 1. DATOS DE BOB Y ALICE ---
    Y_i = Y(:, blk);
    X_i = X(:, blk);
    
    % --- 2. BOB: Mapeo y generación del mensaje público ---
    norm_y = norm(Y_i);
    if norm_y == 0, norm_y = 1.0; end
    Y_norm = Y_i / norm_y;
    
    M_Y = generar_matriz_ortogonal(Y_norm); % Bob construye su matriz 8x8
    
    b_i = bits_bob_all(:, blk);             % Bits aleatorios (0 o 1)
    C_i = 1 - 2*b_i;                        % Mapeo polar (+1 o -1)
    m_i = M_Y' * C_i;                       % El mensaje público (R) que viaja hacia Alice
    
    % --- 3. ALICE: Reconstrucción y cálculo de LLR ---
    norm_x = norm(X_i);
    if norm_x == 0, norm_x = 1.0; end
    X_norm = X_i / norm_x;
    
    % Alice construye su propia matriz con sus medidas cuánticas
    M_X = generar_matriz_ortogonal(X_norm); 
    
    % Alice "deshace" la rotación de Bob mediante multiplicación matricial
    U = M_X * m_i; 
    
    % Cálculo final del LLR (incorporando la energía de ambos vectores)
    LLR_all(:, blk) = inv_sigma2 * norm_x * norm_y * U;
end

llrs_rx = LLR_all(:);
key_bits_tx = bits_bob_all(:);

%% 10. Carga y expansión de la matriz LDPC
bg_matrix = load(fullfile(BOB_DIR, 'NR_1_1_384.txt'));
bg_matrix = load(fullfile(BOB_DIR, 'NR_1_1_384.txt'));
[mb, nb] = size(bg_matrix);
Z = 384;

disp('   Construyendo matriz H dispersa (Lifting)...');
H = sparse(mb*Z, nb*Z);
for i = 1:mb
    for j = 1:nb
        shift = bg_matrix(i,j);
        if shift ~= -1
            I_z = speye(Z);
            circulant = circshift(I_z, [0, shift]);
            H((i-1)*Z+1 : i*Z, (j-1)*Z+1 : j*Z) = circulant;
        end
    end
end

% 4. Cálculo de Síndrome (para verificación del decodificador LDPC de Alice)
% El syndrome se computa como H * key_bits_tx para las 68 columnas reales.
disp('   Calculando Sindrome LDPC (Bloque 1)...');
block_1 = key_bits_tx(1:nb*Z);
syndrome_1 = mod(H * double(block_1), 2);
num_errores_syndrome = sum(syndrome_1);

fprintf('   [!] Bits de Síndrome activos (Ecuaciones fallidas): %d / %d\n', num_errores_syndrome, mb*Z);

%% 10B. RECONCILIACION INVERSA LDPC (Scaled Min-Sum)
disp('   Iniciando decodificacion LDPC (scaled min-sum)...');

alpha = 0.75;
max_iter = 200;
llr_scale = 1.0;

% LLRs de canal para el bloque 1 (soft input de Alice)
llr_ch = llrs_rx(1:nb*Z) * llr_scale;

% Construir listas de vecinos a partir de H
[rows_h, cols_h] = find(H);
num_edges = length(rows_h);
cn_edges = cell(mb*Z, 1);
vn_edges = cell(nb*Z, 1);
for e = 1:num_edges
    cn_edges{rows_h(e)}(end+1) = e;
    vn_edges{cols_h(e)}(end+1) = e;
end

% Mensajes por arista
msg_v2c = zeros(num_edges, 1);
msg_c2v = zeros(num_edges, 1);

% Inicializacion: VN -> CN con LLR de canal
for v = 1:nb*Z
    edges_v = vn_edges{v};
    if ~isempty(edges_v)
        msg_v2c(edges_v) = llr_ch(v);
    end
end

metrics_unsat = zeros(max_iter, 1);
metrics_ber   = zeros(max_iter, 1);
metrics_flips = zeros(max_iter, 1);
bits_prev = zeros(nb*Z, 1);
iter_converged = 0;

p_mem_history = zeros(max_iter, nb, Z);
r_mem_history = zeros(max_iter, mb, nb, Z);

for iter = 1:max_iter
    % --- CN update (scaled min-sum) ---
    for c = 1:mb*Z
        edges_c = cn_edges{c};
        if isempty(edges_c)
            continue;
        end
        msgs = msg_v2c(edges_c);
        abs_vals = abs(msgs);
        sign_vals = sign(msgs);
        sign_vals(sign_vals == 0) = 1;

        min1 = inf;
        min2 = inf;
        count_min1 = 0;
        for k = 1:length(abs_vals)
            a = abs_vals(k);
            if a < min1
                min2 = min1;
                min1 = a;
                count_min1 = 1;
            elseif a == min1
                count_min1 = count_min1 + 1;
            elseif a < min2
                min2 = a;
            end
        end
        if isinf(min2)
            min2 = min1;
        end

        syndrome_sign = 1 - 2 * syndrome_1(c);
        sign_prod = prod(sign_vals) * syndrome_sign;

        for k = 1:length(edges_c)
            if abs_vals(k) == min1 && count_min1 == 1
                min_use = min2;
            else
                min_use = min1;
            end
            sign_excl = sign_prod * sign_vals(k);
            msg_c2v(edges_c(k)) = alpha * sign_excl * min_use;
        end
    end

    % --- VN update ---
    llr_post = zeros(nb*Z, 1);
    for v = 1:nb*Z
        edges_v = vn_edges{v};
        if isempty(edges_v)
            llr_post(v) = llr_ch(v);
        else
            sum_c2v = sum(msg_c2v(edges_v));
            llr_post(v) = llr_ch(v) + sum_c2v;
            msg_v2c(edges_v) = llr_post(v) - msg_c2v(edges_v);
        end
    end

    % --- Hard decision y verificacion de sindrome ---
    bits_est = (llr_post < 0);
    syndrome_est = mod(H * double(bits_est), 2);
    unsat = sum(syndrome_est ~= syndrome_1);
    metrics_unsat(iter) = unsat;
    metrics_ber(iter) = sum(bits_est ~= block_1) / length(block_1);
    metrics_flips(iter) = sum(bits_est ~= bits_prev);
    bits_prev = bits_est;

    % --- Capturar P_mem y R_mem para exportar al Testbench SV ---
    for c_idx = 1:nb
        for z_idx = 1:Z
            p_mem_history(iter, c_idx, z_idx) = llr_post((c_idx-1)*Z + z_idx);
        end
    end
    for e = 1:num_edges
        c_idx = cols_h(e);
        r_idx = rows_h(e);
        block_col = ceil(c_idx / Z);
        block_row = ceil(r_idx / Z);
        z_col = mod(c_idx - 1, Z) + 1;
        r_mem_history(iter, block_row, block_col, z_col) = msg_c2v(e);
    end

    if unsat == 0
        iter_converged = iter;
        fprintf('   [OK] Convergencia LDPC en %d iteraciones (early finish).\n', iter);
        break;
    end
end

if iter_converged == 0
    iter_converged = max_iter;
    fprintf('   [!] No convergio en %d iteraciones.\n', max_iter);
end

fprintf('   -> BER residual (bloque 1): %.6f\n', metrics_ber(iter_converged));
fprintf('   -> Checks no satisfechos (ultima iter): %d\n', metrics_unsat(iter_converged));
fprintf('   -> Flips en ultima iteracion: %d\n', metrics_flips(iter_converged));

%% 11. TABLA DE RESULTADOS Y EXPORTACIÓN
disp('============================================================================');
disp('   MÉTRICA            |   FLOTANTE (Ideal)  |   PUNTO FIJO (FPGA) |  ERROR  ');
disp('----------------------+---------------------+---------------------+---------');
fprintf(' T (Transmitancia) | %19.4f | %19.4f | %7.4f \n', T_eta_ideal, double(T_eta_fp)/65536, abs(T_eta_ideal - double(T_eta_fp)/65536));
fprintf(' Sqrt(T*n)         | %19.4f | %19.4f | %7.4f \n', Sqrt_T_eta_ideal, double(Sqrt_T_eta_fp)/65536, abs(Sqrt_T_eta_ideal - double(Sqrt_T_eta_fp)/65536));
fprintf(' Sigma^2 (Entero)  | %19.4f | %19.4f | %7.4f \n', Sigma_Sq_ideal, double(Sigma_Sq_fp), abs(Sigma_Sq_ideal - double(Sigma_Sq_fp)));
fprintf(' Sigma   (Q16.16)  | %19.4f | %19.4f | %7.4f \n', Sigma_ideal, double(Sigma_fp)/65536, abs(Sigma_ideal - double(Sigma_fp)/65536));
disp('========================================================================');

if ENABLE_EXPORT_VIVADO
    disp('9. Exportando RAMs para Testbench de Vivado...');

    fase_estimada_datos = fase_estimada(idx_datos);
    fase_est_q15 = int32(round(fase_estimada_datos * 32768));

    fid_est = fopen(fullfile(DATA_DIR, 'fase_estimada_datos.txt'), 'w');
    fid_est = fopen(fullfile(DATA_DIR, 'fase_estimada_datos.txt'), 'w');
    for i=1:length(fase_est_q15)
        fprintf(fid_est, '%08X\n', typecast(fase_est_q15(i), 'uint32'));
    end
    fclose(fid_est);

    fases_q15 = int32(round(fase_pilotos_raw * 32768));
    
    fid_pil = fopen(fullfile(DATA_DIR, 'fase_pilotos_raw.txt'), 'w');
    fid_pil = fopen(fullfile(DATA_DIR, 'fase_pilotos_raw.txt'), 'w');
    for i=1:length(fases_q15)
        % Guardamos en Hexadecimal de 32 bits (aunque la FPGA usará los 18 bajos)
        fprintf(fid_pil, '%08X\n', typecast(fases_q15(i), 'uint32'));
    end
    fclose(fid_pil);
    
    fid_ptr = fopen(fullfile(DATA_DIR, 'ptr_ram.txt'), 'w');
    fid_ptr = fopen(fullfile(DATA_DIR, 'ptr_ram.txt'), 'w');
    for i=1:N_SAMPLES, fprintf(fid_ptr, '%04X\n', punteros(i)); end; fclose(fid_ptr);
    
    fid_mask = fopen(fullfile(DATA_DIR, 'mask_bit.txt'), 'w');
    fid_mask = fopen(fullfile(DATA_DIR, 'mask_bit.txt'), 'w');
    for i=1:N_BOB_DATA, fprintf(fid_mask, '%d\n', mascara_sacrificio(i)); end; fclose(fid_mask);
    
    fid_bob = fopen(fullfile(DATA_DIR, 'bob_ram.txt'), 'w');
    fid_bob = fopen(fullfile(DATA_DIR, 'bob_ram.txt'), 'w');
    for i=1:N_BOB_DATA, fprintf(fid_bob, '%04X%04X\n', typecast(Q_B_int(i), 'uint16'), typecast(P_B_int(i), 'uint16')); end; fclose(fid_bob);
    
    fid_alice = fopen(fullfile(DATA_DIR, 'alice_ram.txt'), 'w');
    fid_alice = fopen(fullfile(DATA_DIR, 'alice_ram.txt'), 'w');
    % CUIDADO: La BRAM de Alice solo almacena las 26112 de sacrificio
    for i=1:N_SAMPLES, fprintf(fid_alice, '%04X%04X\n', typecast(Q_A_sac(i), 'uint16'), typecast(P_A_sac(i), 'uint16')); end; fclose(fid_alice);

    fid_exp = fopen(fullfile(DATA_DIR, 'expected_llr_math.txt'), 'w');
    fid_exp = fopen(fullfile(DATA_DIR, 'expected_llr_math.txt'), 'w');
    fprintf(fid_exp, '%08X\n', typecast(int32(T_eta_fp),      'uint32'));
    fprintf(fid_exp, '%08X\n', typecast(int32(Sqrt_T_eta_fp), 'uint32'));
    fprintf(fid_exp, '%08X\n', typecast(int32(Sigma_Sq_fp),   'uint32'));
    fprintf(fid_exp, '%08X\n', typecast(int32(Sigma_fp),      'uint32'));

    % =====================================================================
    % Exportar Datos Crudos (ADC) para el DSP en FPGA
    % Cuantizamos a 16 bits la señal cruda con el ruido de fase INCLUIDO
    % =====================================================================
    P_ADC = int16(round(P_B_rx));
    Q_ADC = int16(round(Q_B_rx));

    fid_adc = fopen(fullfile(DATA_DIR, 'bob_raw_adc.txt'), 'w');
    fid_adc = fopen(fullfile(DATA_DIR, 'bob_raw_adc.txt'), 'w');
    % Guardamos los 52.224 + pilotos (N_FIBER)
    for i=1:N_FIBER
        fprintf(fid_adc, '%04X%04X\n', typecast(Q_ADC(i), 'uint16'), typecast(P_ADC(i), 'uint16'));
    end
    fclose(fid_adc);
    fclose(fid_exp);

    % Alice full 26112 symbols (for MDR RX verification)
    fid_alice_full = fopen(fullfile(DATA_DIR, 'alice_full_data.txt'), 'w');
    fid_alice_full = fopen(fullfile(DATA_DIR, 'alice_full_data.txt'), 'w');
    for i=1:N_BOB_DATA
        fprintf(fid_alice_full, '%04X%04X\n', typecast(Q_A_int(i), 'uint16'), typecast(P_A_int(i), 'uint16'));
    end
    fclose(fid_alice_full);
    % Bob random bits (for MDR TX verification)
    fid_rand = fopen(fullfile(DATA_DIR, 'bob_random_bits.txt'), 'w');
    fid_rand = fopen(fullfile(DATA_DIR, 'bob_random_bits.txt'), 'w');
    bits_flat = bits_bob_all(:);
    for i=1:length(bits_flat)
        fprintf(fid_rand, '%d\n', bits_flat(i));
    end
    fclose(fid_rand);
    % Expected public messages m_i (for MDR TX verification)
    fid_m = fopen(fullfile(DATA_DIR, 'expected_m_messages.txt'), 'w');
    fid_m = fopen(fullfile(DATA_DIR, 'expected_m_messages.txt'), 'w');
    for blk = 1:N_bloques
        Y_i = Y(:, blk);
        Y_norm = Y_i / norm(Y_i);
        M_Y = generar_matriz_ortogonal(Y_norm);
        m_i = M_Y' * (1 - 2*bits_bob_all(:, blk));
        for dim = 1:N_dimensiones
            m_q31 = int32(round(m_i(dim) * 2^31));
            fprintf(fid_m, '%08X\n', typecast(m_q31, 'uint32'));
        end
    end
    fclose(fid_m);
    % Expected LLR results (for MDR RX verification)
    fid_llr = fopen(fullfile(DATA_DIR, 'expected_llr_results.txt'), 'w');
    fid_llr = fopen(fullfile(DATA_DIR, 'expected_llr_results.txt'), 'w');
    for blk = 1:N_bloques
        for dim = 1:N_dimensiones
            llr_fp = int32(round(LLR_all(dim, blk) * 2^31));
            fprintf(fid_llr, '%08X\n', typecast(llr_fp, 'uint32'));
        end
    end
    fclose(fid_llr);

    %% 12. EXPORTAR u_bits.txt CON LLRs REALES (8-BIT SIGN-MAGNITUDE)
    % Para verificacion exacta del decodificador LDPC de Alice
    disp('9. Exportando LLRs reales cuantizados a 8-bit para LDPC...');
    llrs_flat = LLR_all(:);  % 26112x1, column-major

    % Escala optima para 8-bit signed: normalizar a varianza unitaria
    % y escalar para usar ~40% del rango (±48 en 7-bit), preservando
    % diferencias relativas de confianza entre LLRs.
    std_llr = std(llrs_flat);
    if std_llr > 0
        scale_8bit = 48.0 / std_llr;  % ~3 sigma within 8-bit range
    else
        scale_8bit = 48.0 / max(abs(llrs_flat) + eps);
    end

    fid_u = fopen(fullfile(DATA_DIR, 'u_bits.txt'), 'w');
    for col = 0:67
        % $readmemb: primer caracter = MSB (bit 3071) = VNU[Z-1]
        % Escribimos VNUs en orden inverso (Z-1..0) para que
        % VNU[0] quede en los bits [7:0] del bus
        for vnu = Z-1:-1:0
            idx = col * Z + vnu + 1;
            llr_fp = llrs_flat(idx) * scale_8bit;
            llr_s8 = max(-127, min(127, round(llr_fp)));
            sm_val = abs(llr_s8);
            if llr_s8 < 0
                sm_val = bitset(sm_val, 8);
            end
            fprintf(fid_u, '%s', dec2bin(sm_val, 8));
        end
        fprintf(fid_u, '\n');
    end
    fclose(fid_u);
    % Copiar a cvqkd_alice/sim/ para el testbench Verilator
    copyfile(fullfile(DATA_DIR, 'u_bits.txt'), fullfile(ALICE_DATA_DIR, 'u_bits.txt'));
    copyfile(fullfile(DATA_DIR, 'u_bits.txt'), fullfile(ALICE_SIM_DIR, 'u_bits.txt'));
    fprintf('   [OK] u_bits.txt exportado (68 x %d bits, scale=%.2f)\n', Z*8, scale_8bit);

    % --- Exportar P_mem y R_mem iteracion a iteracion ---
    disp('   Exportando P_mem y R_mem intermedios para debugging SV...');
    fid_p = fopen(fullfile(DATA_DIR, 'expected_p_mem.txt'), 'w');
    fid_r = fopen(fullfile(DATA_DIR, 'expected_r_mem.txt'), 'w');
    for it = 1:iter_converged
        for c = 1:nb
            for vnu = Z:-1:1
                val_fp = p_mem_history(it, c, vnu);
                val_s8 = max(-127, min(127, round(val_fp * scale_8bit)));
                sm_mag = abs(val_s8);
                sm_sign = uint16(val_s8 < 0);
                val_16 = bitshift(sm_sign, 15) + uint16(sm_mag);
                fprintf(fid_p, '%04X', val_16);
            end
            fprintf(fid_p, '\n');
        end
        for r = 1:mb
            for c = 1:nb
                for vnu = Z:-1:1
                    val_fp = r_mem_history(it, r, c, vnu);
                    val_s8 = max(-127, min(127, round(val_fp * scale_8bit)));
                    sm_mag = abs(val_s8);
                    sm_sign = uint16(val_s8 < 0);
                    val_16 = bitshift(sm_sign, 15) + uint16(sm_mag);
                    fprintf(fid_r, '%04X', val_16);
                end
                fprintf(fid_r, '\n');
            end
        end
    end
    fclose(fid_p);
    fclose(fid_r);
    copyfile(fullfile(DATA_DIR, 'expected_p_mem.txt'), fullfile(ALICE_SIM_DIR, 'expected_p_mem.txt'));
    copyfile(fullfile(DATA_DIR, 'expected_r_mem.txt'), fullfile(ALICE_SIM_DIR, 'expected_r_mem.txt'));
    disp('   [OK] expected_p_mem.txt y expected_r_mem.txt exportados');

    % Expected key bits for LDPC decoder verification (bob_key_ref.txt)
    % 68 lines of 384 binary digits each; one line per column
    fid_key = fopen(fullfile(DATA_DIR, 'bob_key_ref.txt'), 'w');
    for blk = 0:67
        for bit = 1:Z
            fprintf(fid_key, '%d', key_bits_tx(blk*Z + bit));
        end
        fprintf(fid_key, '\n');
    end
    fclose(fid_key);
    copyfile(fullfile(DATA_DIR, 'bob_key_ref.txt'), fullfile(ALICE_DATA_DIR, 'bob_key_ref.txt'));
    copyfile(fullfile(DATA_DIR, 'bob_key_ref.txt'), fullfile(ALICE_SIM_DIR, 'bob_key_ref.txt'));
    disp('   [OK] bob_key_ref.txt exportado (68 x 384 bits)');
    
    % Export expected syndrome: 46 rows x 384 bits
    % $readmemb: first char -> MSB (bit[383])
    fid_syn = fopen(fullfile(DATA_DIR, 'expected_syndrome.txt'), 'w');
    for row = 0:mb-1
        row_bits = syndrome_1(row*Z+1 : row*Z+Z);
        for bit = 1:Z
            fprintf(fid_syn, '%d', row_bits(bit));
        end
        fprintf(fid_syn, '\n');
    end
    fclose(fid_syn);
    copyfile(fullfile(DATA_DIR, 'expected_syndrome.txt'), fullfile(ALICE_DATA_DIR, 'expected_syndrome.txt'));
    copyfile(fullfile(DATA_DIR, 'expected_syndrome.txt'), fullfile(ALICE_SIM_DIR, 'expected_syndrome.txt'));
    disp('   [OK] expected_syndrome.txt exportado (46 x 384 bits)');
    % Expected key bits for LDPC decoder verification (bob_key_ref.txt)
    % 68 lines of 384 binary digits each; line 0 is the reference key block
    fid_key = fopen(fullfile(DATA_DIR, 'bob_key_ref.txt'), 'w');
    ref_block = key_bits_tx(1:Z);  % First Z=384 bits of the original key
    for blk = 1:68
        for bit = 1:Z
            fprintf(fid_key, '%d', ref_block(bit));
        end
        fprintf(fid_key, '\n');
    end
    fclose(fid_key);
    disp('   [OK] bob_key_ref.txt exportado (68 x 384 bits)');
    
    disp('   [OK] Archivos de simulación generados con éxito.');
    
    %% 13. DUMP DE DEPURACIÓN PARA TESTBENCH AISLADO DE CNU
    % =========================================================================
    % Extrae las entradas (Q, P) y salidas (R) exactas para los 384 CNUs 
    % correspondientes a la FILA 1 en la ITERACIÓN 1, alineando los datos 
    % como si pasaran por el Barrel Shifter del hardware.
    % IMPORTANTE: Cuantizamos PRIMERO a 8-bit y luego ejecutamos Min-Sum
    % con los valores cuantizados para que coincida con el RTL.
    % =========================================================================
    disp('10. Generando archivos de depuración aislada para CNU...');

    f_q = fopen(fullfile(DATA_DIR, 'cnu_tb_q_in.txt'), 'w');
    f_p = fopen(fullfile(DATA_DIR, 'cnu_tb_p_in.txt'), 'w');
    f_r = fopen(fullfile(DATA_DIR, 'cnu_tb_r_out.txt'), 'w');

    % Función lambda para convertir a Binario de 16-bits (Signo-Magnitud)
    to_sm16_bin = @(val_fp) dec2bin( ...
        bitshift(uint16(max(-127, min(127, round(val_fp * scale_8bit))) < 0), 15) + ...
        uint16(abs(max(-127, min(127, round(val_fp * scale_8bit))))), 16 );

    % --- 1. Cuantizar LLRs de entrada a 8-bit (igual que el RTL) ---
    q_quantized = zeros(nb * Z, 1);
    for v = 1:nb*Z
        llr_fp = llr_ch(v) * scale_8bit;
        llr_s8 = max(-127, min(127, round(llr_fp)));
        q_quantized(v) = double(llr_s8);
    end

    % --- 2. Ejecutar Min-Sum con valores cuantizados (fila 0, iteración 1) ---
    alpha = 0.75;

    min1_arr = inf(Z, 1);
    min2_arr = inf(Z, 1);
    min1_idx_arr = zeros(Z, 1);
    total_sign = zeros(Z, 1);

    syndrome_row = syndrome_1(1:Z);
    total_sign = double(syndrome_row);

    % Fase READ: recorrer todas las columnas válidas
    for c_idx = 1:nb
        shift = bg_matrix(1, c_idx);
        if shift == -1
            continue;
        end
        
        vn_vals = q_quantized((c_idx-1)*Z + 1 : c_idx*Z);
        vn_aligned = circshift(vn_vals, -shift);
        
        q_sign = double(vn_aligned < 0);
        q_mag = abs(vn_aligned);
        
        total_sign = mod(total_sign + q_sign, 2);
        
        for z = 1:Z
            if q_mag(z) < min1_arr(z)
                min2_arr(z) = min1_arr(z);
                min1_arr(z) = q_mag(z);
                min1_idx_arr(z) = c_idx - 1;
            elseif q_mag(z) < min2_arr(z)
                min2_arr(z) = q_mag(z);
            end
        end
    end

    % Fase WRITE: calcular r_new para cada columna
    r_quantized = zeros(nb, Z);

    for c_idx = 1:nb
        shift = bg_matrix(1, c_idx);
        if shift == -1
            continue;
        end
        
        vn_vals = q_quantized((c_idx-1)*Z + 1 : c_idx*Z);
        vn_aligned = circshift(vn_vals, -shift);
        q_sign = double(vn_aligned < 0);
        
        for z = 1:Z
            if (c_idx - 1) == min1_idx_arr(z)
                raw_mag = min2_arr(z);
            else
                raw_mag = min1_arr(z);
            end
            
            norm_mag = raw_mag - floor(raw_mag / 4);
            
            r_sign = total_sign(z);
            
            if r_sign
                r_val = -double(norm_mag);
            else
                r_val = double(norm_mag);
            end
            r_quantized(c_idx, z) = r_val;
        end
    end

    % --- 3. Exportar archivos ---
    for c_idx = 1:nb
        shift = bg_matrix(1, c_idx);
        
        Q_aligned = zeros(Z, 1);
        P_aligned = zeros(Z, 1);
        R_aligned = zeros(Z, 1);
        
        if shift ~= -1
            vn_vals = q_quantized((c_idx-1)*Z + 1 : c_idx*Z);
            Q_aligned = circshift(vn_vals, -shift);
            P_aligned = Q_aligned;
            R_aligned = r_quantized(c_idx, :)';
        end
        
        for z_idx = Z:-1:1
            fprintf(f_q, '%s', to_sm16_bin(Q_aligned(z_idx))); 
            fprintf(f_p, '%s', to_sm16_bin(P_aligned(z_idx)));
            fprintf(f_r, '%s', to_sm16_bin(R_aligned(z_idx)));
        end
        
        fprintf(f_q, '\n'); 
        fprintf(f_p, '\n'); 
        fprintf(f_r, '\n');
    end

    fclose(f_q); 
    fclose(f_p); 
    fclose(f_r);

    copyfile(fullfile(DATA_DIR, 'cnu_tb_q_in.txt'), fullfile(ALICE_SIM_DIR, 'cnu_tb_q_in.txt'));
    copyfile(fullfile(DATA_DIR, 'cnu_tb_p_in.txt'), fullfile(ALICE_SIM_DIR, 'cnu_tb_p_in.txt'));
    copyfile(fullfile(DATA_DIR, 'cnu_tb_r_out.txt'), fullfile(ALICE_SIM_DIR, 'cnu_tb_r_out.txt'));

    disp('    [OK] Archivos cnu_tb_q_in.txt, cnu_tb_p_in.txt y cnu_tb_r_out.txt exportados con éxito.');
    disp('    [OK] Referencia R generada con Min-Sum cuantizado (alpha=0.75).');
end