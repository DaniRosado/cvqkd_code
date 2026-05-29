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

%% 0.1. PARÁMETROS DEL SISTEMA
ENABLE_EXPORT_VIVADO = true;
ENABLE_GRAFICAS = false;

% --- Parámetros de Trama y Memoria ---
L_trama     = 16;      % 1 Piloto + 15 Datos
N_BOB_DATA  = 52224/2;   % Datos útiles que caben en la RAM de Bob
N_FRAMES    = ceil(N_BOB_DATA / 15); % ~3482 tramas
N_SAMPLES   = 26112/2;   % Datos sacrificados para la estimación

% En la fibra viajan los datos + los pilotos. Sumamos 1 piloto final para interpolar
N_FIBER     = N_FRAMES * L_trama + 1; 

% --- Parámetros Físicos del Canal ---
Ts           = 1e-9;   % Tiempo de símbolo (1 Gbaud)
T_real       = 0.5;    % Transmitancia real de la fibra
xi_real      = 0.02;   % Ruido en exceso cuántico (SNU)
V_A_snu      = 4.0;    % Varianza de Alice (SNU)
V_elec_snu   = 0.1;    % Ruido electrónico (SNU)
eta_detector = 0.6;    % Eficiencia del fotodiodo

% --- Calibración del Hardware (ADC) ---
N0_adc_var   = 10000;  % Varianza para 1 SNU
Amp_Piloto   = 20000;  % Amplitud fuerte para el pulso piloto (para no perder fase)

%% 1. MODELO DE RUIDO DE FASE DEL CANAL (Tu código integrado)
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

%% 2. ALICE: GENERACIÓN CUÁNTICA CON PILOTOS INTERCALADOS
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

%% 3. EL CANAL: ATENUACIÓN Y AWGN
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

%% 4. RECEPCIÓN Y DSP DE BOB (Recuperación de Fase Vectorizada)
disp('4. DSP de Bob: Siguiendo y deshaciendo la fase (Unwrap)...');

% 1. Extracción de los pilotos recibidos y cálculo de su fase cruda
P_pilotos_rx = P_B_rx(idx_pilotos);
Q_pilotos_rx = Q_B_rx(idx_pilotos);

fase_pilotos_raw = atan2(Q_pilotos_rx, P_pilotos_rx);

% 2. EL SECRETO: Desenrollar la fase para evitar saltos de 2*pi
fase_pilotos_limpia = unwrap(fase_pilotos_raw);

% 3. Interpolación lineal para estimar la fase de todos los símbolos
% (interp1 interpola los huecos de los datos basándose en los pilotos)
fase_estimada = interp1(idx_pilotos, fase_pilotos_limpia, (1:N_FIBER)', 'linear');

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

%% 5. SELECCIÓN DE PUNTEROS Y ESTIMACIÓN FLOTANTE (MATLAB IDEAL)
disp('5. Seleccionando muestras de sacrificio y calculando métricas...');
punteros = randperm(N_BOB_DATA, N_SAMPLES)' - 1;

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

%% 6. EMULACIÓN PUNTO FIJO (LLR_Math_Unit FPGA)
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

%% 7. GRÁFICAS DEL GEMELO DIGITAL
if ENABLE_GRAFICAS
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
end

%% 8. RECONCILIACIÓN MULTIDIMENSIONAL (8D) Y EXTRACCIÓN DE LLRs
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

%% 9. Carga y expansión de la matriz LDPC
disp('9. Carga matriz LDPC y Sindrome...');

bg_matrix = load(fullfile(BOB_DIR, 'NR_1_1_384.txt'));
[mb, nb] = size(bg_matrix);
Z = 384;

disp('   9.1. Construyendo matriz H dispersa (Lifting)...');
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
disp('   9.2. Calculando Sindrome LDPC (Bloque 1)...');
block_1 = key_bits_tx(1:nb*Z);
syndrome_1 = mod(H * double(block_1), 2);
num_errores_syndrome = sum(syndrome_1);

fprintf('   9.3. [!] Bits de Síndrome activos (Ecuaciones fallidas): %d / %d\n', num_errores_syndrome, mb*Z);

%% 10. RECONCILIACION INVERSA LDPC (Scaled Min-Sum)
disp('10. Iniciando decodificacion LDPC (scaled min-sum)...');

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

%% 11. GENERADOR DE ROM SYSTEMVERILOG ---
disp('11. Generando ROM System Verilog');
fileID = fopen('bg1_rom_pkg.sv', 'w');

fprintf(fileID, 'package bg1_rom_pkg;\n\n');

% Estructuras
fprintf(fileID, '    typedef struct packed {\n');
fprintf(fileID, '        logic [8:0] start_ptr;\n');
fprintf(fileID, '        logic [5:0] num_edges;\n');
fprintf(fileID, '    } row_info_t;\n\n');

fprintf(fileID, '    typedef struct packed {\n');
fprintf(fileID, '        logic [6:0] col_idx;\n');
fprintf(fileID, '        logic [8:0] shift_val;\n');
fprintf(fileID, '    } edge_info_t;\n\n');

% 1. Generar EDGE_ROM
fprintf(fileID, '    localparam edge_info_t EDGE_ROM [0:315] = ''{\n');
ptr = 0;
row_start = zeros(46, 1);
row_edges = zeros(46, 1);

for r = 1:46
    row_start(r) = ptr;
    edges_in_this_row = 0;
    for c = 1:68
        shift = bg_matrix(r, c);
        if shift ~= -1
            fprintf(fileID, '        %d: ''{col_idx: 7''d%d, shift_val: 9''d%d}', ptr, c-1, shift);
            ptr = ptr + 1;
            edges_in_this_row = edges_in_this_row + 1;
            if ptr < 316
                fprintf(fileID, ',\n');
            else
                fprintf(fileID, '\n');
            end
        end
    end
    row_edges(r) = edges_in_this_row;
end
fprintf(fileID, '    };\n\n');

% 2. Generar ROW_INFO_ROM
fprintf(fileID, '    localparam row_info_t ROW_INFO_ROM [0:45] = ''{\n');
for r = 1:46
    fprintf(fileID, '        %d: ''{start_ptr: 9''d%d, num_edges: 6''d%d}', r-1, row_start(r), row_edges(r));
    if r < 46
        fprintf(fileID, ',\n');
    else
        fprintf(fileID, '\n');
    end
end
fprintf(fileID, '    };\n\n');

fprintf(fileID, 'endpackage\n');
fclose(fileID);
disp('   ¡Archivo bg1_rom_pkg.sv generado con éxito!');

%% 12. TABLA DE RESULTADOS Y EXPORTACIÓN
disp('============================================================================');
disp('   MÉTRICA            |   FLOTANTE (Ideal)  |   PUNTO FIJO (FPGA) |  ERROR  ');
disp('----------------------+---------------------+---------------------+---------');
fprintf(' T (Transmitancia) | %19.4f | %19.4f | %7.4f \n', T_eta_ideal, double(T_eta_fp)/65536, abs(T_eta_ideal - double(T_eta_fp)/65536));
fprintf(' Sqrt(T*n)         | %19.4f | %19.4f | %7.4f \n', Sqrt_T_eta_ideal, double(Sqrt_T_eta_fp)/65536, abs(Sqrt_T_eta_ideal - double(Sqrt_T_eta_fp)/65536));
fprintf(' Sigma^2 (Entero)  | %19.4f | %19.4f | %7.4f \n', Sigma_Sq_ideal, double(Sigma_Sq_fp), abs(Sigma_Sq_ideal - double(Sigma_Sq_fp)));
fprintf(' Sigma   (Q16.16)  | %19.4f | %19.4f | %7.4f \n', Sigma_ideal, double(Sigma_fp)/65536, abs(Sigma_ideal - double(Sigma_fp)/65536));
disp('========================================================================');

if ENABLE_EXPORT_VIVADO
    disp('12. Exportando RAMs y vectores de verificación para Vivado...');

    % 1. SEÑALES CRUDAS (ADC) - Lo primero que entra en el DSP
    fid_adc = fopen(fullfile(DATA_DIR, 'bob_raw_adc.txt'), 'w');
    P_ADC = int16(round(P_B_rx)); Q_ADC = int16(round(Q_B_rx));
    for i=1:N_FIBER
        fprintf(fid_adc, '%04X%04X\n', typecast(Q_ADC(i), 'uint16'), typecast(P_ADC(i), 'uint16'));
    end
    fclose(fid_adc);

    % 2. DSP: Fase (Pilotos y Estimación)
    % Fase cruda de pilotos
    fid_pil = fopen(fullfile(DATA_DIR, 'fase_pilotos_raw.txt'), 'w');
    fases_q15 = int32(round(fase_pilotos_raw * 32768));
    for i=1:length(fases_q15)
        fprintf(fid_pil, '%08X\n', typecast(fases_q15(i), 'uint32'));
    end
    fclose(fid_pil);

    % Fase interpolada para los datos
    fid_est = fopen(fullfile(DATA_DIR, 'fase_estimada_datos.txt'), 'w');
    fase_est_q15 = int32(round(fase_estimada(idx_datos) * 32768));
    for i=1:length(fase_est_q15)
        fprintf(fid_est, '%08X\n', typecast(fase_est_q15(i), 'uint32'));
    end
    fclose(fid_est);

    % 3. MDR: Datos de Reconciliación (Alice/Bob, Bits, Mensajes)
    fid_alice_full = fopen(fullfile(DATA_DIR, 'alice_full_data.txt'), 'w');
    fid_bob = fopen(fullfile(DATA_DIR, 'bob_ram.txt'), 'w');
    for i=1:N_BOB_DATA
        fprintf(fid_alice_full, '%04X%04X\n', typecast(Q_A_int(i), 'uint16'), typecast(P_A_int(i), 'uint16'));
        fprintf(fid_bob, '%04X%04X\n', typecast(Q_B_int(i), 'uint16'), typecast(P_B_int(i), 'uint16'));
    end
    fclose(fid_alice_full); fclose(fid_bob);

    fid_rand = fopen(fullfile(DATA_DIR, 'bob_random_bits.txt'), 'w');
    for i=1:length(bits_bob_all(:)), fprintf(fid_rand, '%d\n', bits_bob_all(i)); end
    fclose(fid_rand);

    fid_m = fopen(fullfile(DATA_DIR, 'expected_m_messages.txt'), 'w');
    for blk = 1:N_bloques
        Y_norm = Y(:, blk) / norm(Y(:, blk));
        m_i = generar_matriz_ortogonal(Y_norm)' * (1 - 2*bits_bob_all(:, blk));
        for dim = 1:N_dimensiones
            fprintf(fid_m, '%08X\n', typecast(int32(round(m_i(dim) * 2^31)), 'uint32'));
        end
    end
    fclose(fid_m);

    % 4. LDPC / LLRs: Punteros, Máscaras y Resultados Finales
    fid_ptr = fopen(fullfile(DATA_DIR, 'ptr_ram.txt'), 'w');
    for i=1:N_SAMPLES, fprintf(fid_ptr, '%04X\n', punteros(i)); end; fclose(fid_ptr);

    fid_mask = fopen(fullfile(DATA_DIR, 'mask_bit.txt'), 'w');
    for i=1:N_BOB_DATA, fprintf(fid_mask, '%d\n', mascara_sacrificio(i)); end; fclose(fid_mask);

    fid_alice = fopen(fullfile(DATA_DIR, 'alice_ram.txt'), 'w');
    for i=1:N_SAMPLES, fprintf(fid_alice, '%04X%04X\n', typecast(Q_A_sac(i), 'uint16'), typecast(P_A_sac(i), 'uint16')); end; fclose(fid_alice);

    fid_llr = fopen(fullfile(DATA_DIR, 'expected_llr_results.txt'), 'w');
    for i=1:length(LLR_all(:))
        fprintf(fid_llr, '%08X\n', typecast(int32(round(LLR_all(i) * 2^31)), 'uint32'));
    end
    fclose(fid_llr);

    % Exportacion de los LLRs en formato Signo-magnitud (8bits)
    std_llr = std(llrs_rx); 
    if std_llr > 0
        scale = 48.0 / std_llr; % Escala conservadora para evitar saturación
    else
        scale = 1.0;
    end
    
    llr_int = round(llrs_rx * scale); 
    
    % Crear vector de 8 bits (tipo uint8)
    llr_sm = zeros(length(llr_int), 1, 'uint8');
    
    for i = 1:length(llr_int)
        val = llr_int(i);
        mag = abs(val);
        
        % Saturar a 127 (máximo valor para 7 bits de magnitud)
        if mag > 127, mag = 127; end
        
        % Asignar signo: Si val < 0, poner bit 7 a 1
        if val < 0
            llr_sm(i) = uint8(mag) + 128; % 128 es el bit 7 activo (10000000)
        else
            llr_sm(i) = uint8(mag);
        end
    end
    
    fid = fopen(fullfile(DATA_DIR, 'u_bits.txt'), 'w');
    for i = 1:length(llr_sm)
        fprintf(fid, '%s\n', dec2bin(llr_sm(i), 8));
    end
    fclose(fid);

    % 5. MÉTRICAS (Resultados finales de la Math Unit)
    fid_exp = fopen(fullfile(DATA_DIR, 'expected_llr_math.txt'), 'w');
    fprintf(fid_exp, '%08X\n', typecast(int32(T_eta_fp), 'uint32'));
    fprintf(fid_exp, '%08X\n', typecast(int32(Sqrt_T_eta_fp), 'uint32'));
    fprintf(fid_exp, '%08X\n', typecast(int32(Sigma_Sq_fp), 'uint32'));
    fprintf(fid_exp, '%08X\n', typecast(int32(Sigma_fp), 'uint32'));
    fclose(fid_exp);

     % Exportar Acumuladores (para tb_LLR_Math_Unit)
    fid_acc = fopen(fullfile(DATA_DIR, 'accumulators.txt'), 'w');
    fprintf(fid_acc, '%016X\n', typecast(int64(sum_sq_P_B), 'uint64'));
    fprintf(fid_acc, '%016X\n', typecast(int64(sum_P_B),    'uint64'));
    fprintf(fid_acc, '%016X\n', typecast(int64(sum_cov_P),  'uint64'));
    fprintf(fid_acc, '%016X\n', typecast(int64(sum_P_A),    'uint64'));
    fprintf(fid_acc, '%016X\n', typecast(int64(sum_sq_Q_B), 'uint64'));
    fprintf(fid_acc, '%016X\n', typecast(int64(sum_Q_B),    'uint64'));
    fprintf(fid_acc, '%016X\n', typecast(int64(sum_cov_Q),  'uint64'));
    fprintf(fid_acc, '%016X\n', typecast(int64(sum_Q_A),    'uint64'));
    fclose(fid_acc);
end