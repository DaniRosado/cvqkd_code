2%% ========================================================================
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
N_BOB_DATA  = 26112;   % Datos útiles que caben en la RAM de Bob
N_FRAMES    = ceil(N_BOB_DATA / 15); % ~3482 tramas
N_SAMPLES   = N_BOB_DATA/2;   % Datos sacrificados para la estimación

% En la fibra viajan los datos + los pilotos. Sumamos 1 piloto final para interpolar
N_FIBER     = N_FRAMES * L_trama + 1; 

% --- Parámetros Físicos del Canal ---
Ts           = 1e-9;   % Tiempo de símbolo (1 Gbaud)
T_real       = 0.45;    % Transmitancia real de la fibra
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

% 1. Filtramos con la máscara (Criba clásica). 
% ¡VITAL! Usamos los arrays _int para partir de los datos EXACTAMENTE cuantizados
% que ve la FPGA, no de los floats puros. Esto elimina errores de redondeo en el testbench.
idx_key = find(mascara_sacrificio == 0);

P_A_key = double(P_A_int(idx_key));
Q_A_key = double(Q_A_int(idx_key));
P_B_key = double(P_B_int(idx_key));
Q_B_key = double(Q_B_int(idx_key));

N_dimensiones = 8;
symbols_per_block = N_dimensiones / 2; % 4 simbolos complejos -> 8D
N_bloques = floor(length(P_B_key) / symbols_per_block); % AHORA SÍ: 3264 bloques útiles

num_used = N_bloques * symbols_per_block;
P_A_mdr = P_A_key(1:num_used); 
Q_A_mdr = Q_A_key(1:num_used);
P_B_mdr = P_B_key(1:num_used);
Q_B_mdr = Q_B_key(1:num_used);

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
K_dyn_all = zeros(1, N_bloques);

for blk = 1:N_bloques
    % --- 1. DATOS DE BOB Y ALICE ---
    Y_i = Y(:, blk);
    X_i = X(:, blk);
    
    % --- 2. BOB: Mapeo y generación del mensaje público ---
    norm_y = norm(Y_i);
    if norm_y == 0, norm_y = 1.0; end
    Y_norm = Y_i / norm_y;
    
    M_Y = generar_matriz_ortogonal(Y_norm); % Bob construye su matriz
    
    b_i = bits_bob_all(:, blk);             % Bits aleatorios
    C_i = 1 - 2*b_i;                        % Mapeo polar
    m_i = M_Y' * C_i;                       % Mensaje público
    
    % --- 3. ALICE: Reconstrucción y cálculo de LLR ---
    % Dejamos norm_x a 1 porque tu Datapath de Alice asume X sin normalizar por eficiencia
    norm_x = 1.0; 
    X_norm = X_i / norm_x;
    
    M_X = generar_matriz_ortogonal(X_norm); 
    U = M_X * m_i; 
    
    LLR_all(:, blk) = inv_sigma2 * norm_x * norm_y * U ;
    K_dyn_all(blk) = inv_sigma2 * norm_y;
end

llrs_rx = LLR_all(:);
key_bits_tx = bits_bob_all(:);

if ENABLE_EXPORT_VIVADO
    disp('   -> Exportando archivos para el Datapath de Alice...');

    % 1. Entradas X crudas de Alice (128 bits por línea)
    fid_alice_in = fopen(fullfile(DATA_DIR, 'alice_mdr_inputs.txt'), 'w');
    for blk = 1:N_bloques
        X_int16 = int16(X(:, blk));
        bin_str = '';
        for dim = 8:-1:1
            bin_str = [bin_str, dec2hex(typecast(X_int16(dim), 'uint16'), 4)];
        end
        fprintf(fid_alice_in, '%s\n', bin_str);
    end
    fclose(fid_alice_in);

    % 2. Factor K dinámico del ARM (Formato Q10 para balancear bits, 1 por línea)
    % Usamos Q10 porque K_dyn suele ser un número grande (decenas de miles)
    fid_k = fopen(fullfile(DATA_DIR, 'alice_k_dynamic.txt'), 'w');
    for blk = 1:N_bloques
        k_q10 = int32(round(K_dyn_all(blk) * 2^10));
        fprintf(fid_k, '%08X\n', typecast(k_q10, 'uint32'));
    end
    fclose(fid_k);

    % 3. LLRs Esperados en formato Signo-Magnitud 8-bits
    fid_llr_hw = fopen(fullfile(DATA_DIR, 'expected_llrs_hardware.txt'), 'w');
    for blk = 1:N_bloques
        for dim = 1:8
            val = round(LLR_all(dim, blk));
            
            % Saturador L_BRAM
            if val > 127,  val = 127;  end
            if val < -127, val = -127; end
            
            if val < 0
                sm_val = 128 + abs(val); % Bit 7 a 1 (Negativo)
            else
                sm_val = val;            % Bit 7 a 0 (Positivo)
            end
            fprintf(fid_llr_hw, '%02X\n', sm_val);
        end
    end
    fclose(fid_llr_hw);
end

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
max_iter = 100; % Limitado a 2 iteraciones para verificar el cambio de iteración
llr_scale = 1;

% 1. Cálculo en flotante
llr_ch_float = llrs_rx(1:nb*Z) * llr_scale;

% 2. Cuantización (Redondeo al entero más cercano)
llr_ch_int = round(llr_ch_float);

% 3. Saturación al límite del hardware de 8-bits Signo-Magnitud (-127 a +127)
llr_ch_int(llr_ch_int > 127) = 127;
llr_ch_int(llr_ch_int < -127) = -127;

% 4. Inyectamos la versión "hardware" al decodificador
llr_ch = llr_ch_int;

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


% =========================================================================
% DECODIFICACIÓN LAYERED (Idéntica al hardware)
% Cada fila del base graph se procesa completamente (CN update + VN update
% inmediato) antes de pasar a la siguiente. Así la fila N+1 lee los LLR
% ya actualizados por la fila N, igual que el hardware escribe en L_BRAM.
%
% L_write_history: captura lo que el hardware escribiría en L_BRAM en cada
% edge, en el mismo orden que EDGE_ROM (para el auto-checker de Vivado).
% =========================================================================
L_write_history = cell(0, 1); % Cada celda = vector de Z valores (un edge)

for iter = 1:max_iter

    for row = 1:mb
        % Rango de check-nodes de esta fila (layer)
        cn_start = (row-1)*Z + 1;
        cn_end   = row*Z;

        % --- CN update para los Z check-nodes de esta fila ---
        for c = cn_start:cn_end
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

                % Escalado hardware: val - (val >> 2) = 0.75 * val
                min_scaled = min_use - bitshift(min_use, -2);
                raw_msg = sign_excl * min_scaled;

                msg_c2v(edges_c(k)) = raw_msg;
            end
        end

        % --- VN update INMEDIATO (solo las columnas afectadas por esta fila) ---
        % En hardware: Pasada 1 recorre los edges de esta fila y para cada
        % columna escribe L_write = L_q + R_new en la L_BRAM.
        % El orden de recorrido es el del EDGE_ROM: columnas activas de
        % bg_matrix(row,:) de izquierda a derecha.
        valid_cols_row = find(bg_matrix(row, :) ~= -1);

        for ei = 1:length(valid_cols_row)
            col_bg = valid_cols_row(ei); % Columna del base graph (1-based)

            % Rango de VNs de este bloque Z
            vn_start = (col_bg-1)*Z + 1;
            vn_end   = col_bg*Z;

            % Calcular L_write para cada posición z de esta columna
            L_write_block = zeros(1, Z);
            for z = 1:Z
                v = vn_start + z - 1;
                edges_v = vn_edges{v};
                L_write_block(z) = llr_ch(v) + sum(msg_c2v(edges_v));
                % Saturación idéntica al hardware (VNU satura a ±127 al escribir en L_BRAM)
                if L_write_block(z) > 127, L_write_block(z) = 127; end
                if L_write_block(z) < -127, L_write_block(z) = -127; end
            end

            % Capturar para el auto-checker
            L_write_history{end+1, 1} = L_write_block;

            % Actualizar msg_v2c para que la siguiente fila lea valores frescos
            % Saturar a ±127 como hace el VNU en hardware (L_q = L_read - R_old)
            for z = 1:Z
                v = vn_start + z - 1;
                edges_v = vn_edges{v};
                llr_post_v = L_write_block(z);
                lq = llr_post_v - msg_c2v(edges_v);
                lq(lq > 127) = 127;
                lq(lq < -127) = -127;
                msg_v2c(edges_v) = lq;
            end
        end
    end

    % --- VN update global (para tener llr_post completo) ---
    llr_post = zeros(nb*Z, 1);
    for v = 1:nb*Z
        edges_v = vn_edges{v};
        if isempty(edges_v)
            llr_post(v) = llr_ch(v);
        else
            llr_post(v) = llr_ch(v) + sum(msg_c2v(edges_v));
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
    disp('9. Exportando RAMs para Testbench de Vivado...');

    % =====================================================================
    % Exportar Decisiones Fuertes (block_bits.txt) para tb_syndrome_calc
    % =====================================================================
    block_matrix = reshape(block_1, Z, nb).';
    
    fid_bb = fopen(fullfile(DATA_DIR, 'block_bits.txt'), 'w');
    for c = 1:nb
        % Escribimos al revés (Z bajando a 1) para el Endianness de SystemVerilog
        fprintf(fid_bb, '%d', block_matrix(c, Z:-1:1));
        fprintf(fid_bb, '\n');
    end
    fclose(fid_bb);
    disp('   -> block_bits.txt generado con éxito (68 líneas x 384 bits).');

    fase_estimada_datos = fase_estimada(idx_datos);
    fase_est_q15 = int32(round(fase_estimada_datos * 32768));

    fid_est = fopen(fullfile(DATA_DIR, 'fase_estimada_datos.txt'), 'w');
    for i=1:length(fase_est_q15)
        fprintf(fid_est, '%08X\n', typecast(fase_est_q15(i), 'uint32'));
    end
    fclose(fid_est);

    fases_q15 = int32(round(fase_pilotos_raw * 32768));
    
    fid_pil = fopen(fullfile(DATA_DIR, 'fase_pilotos_raw.txt'), 'w');
    for i=1:length(fases_q15)
        % Guardamos en Hexadecimal de 32 bits (aunque la FPGA usará los 18 bajos)
        fprintf(fid_pil, '%08X\n', typecast(fases_q15(i), 'uint32'));
    end
    fclose(fid_pil);

    fid_ptr = fopen(fullfile(DATA_DIR, 'ptr_ram.txt'), 'w');
    for i=1:N_SAMPLES, fprintf(fid_ptr, '%04X\n', punteros(i)); end; fclose(fid_ptr);

    fid_mask = fopen(fullfile(DATA_DIR, 'mask_bit.txt'), 'w');
    for i=1:N_BOB_DATA, fprintf(fid_mask, '%d\n', mascara_sacrificio(i)); end; fclose(fid_mask);

    fid_bob = fopen(fullfile(DATA_DIR, 'bob_ram.txt'), 'w');
    for i=1:N_BOB_DATA, fprintf(fid_bob, '%04X%04X\n', typecast(Q_B_int(i), 'uint16'), typecast(P_B_int(i), 'uint16')); end; fclose(fid_bob);

    fid_alice = fopen(fullfile(DATA_DIR, 'alice_ram.txt'), 'w');
    % CUIDADO: La BRAM de Alice solo almacena las 26112 de sacrificio
    for i=1:N_SAMPLES, fprintf(fid_alice, '%04X%04X\n', typecast(Q_A_sac(i), 'uint16'), typecast(P_A_sac(i), 'uint16')); end; fclose(fid_alice);

    fid_exp = fopen(fullfile(DATA_DIR, 'expected_llr_math.txt'), 'w');
    fprintf(fid_exp, '%08X\n', typecast(int32(T_eta_fp),      'uint32'));
    fprintf(fid_exp, '%08X\n', typecast(int32(Sqrt_T_eta_fp), 'uint32'));
    fprintf(fid_exp, '%08X\n', typecast(int32(Sigma_Sq_fp),   'uint32'));
    fprintf(fid_exp, '%08X\n', typecast(int32(Sigma_fp),      'uint32'));
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

    % =====================================================================
    % EXPORTAR ENTRADAS MDR BOB (Bloques de 8 dimensiones en 16-bits)
    % =====================================================================
    disp('   -> Exportando bob_mdr_inputs.txt para Vivado (Bloques 8D)...');
    fid_mdr_in = fopen(fullfile(DATA_DIR, 'bob_mdr_inputs.txt'), 'w');

    for blk = 1:N_bloques
        % Y(:, blk) tiene las 8 coordenadas en doble precisión en la simulación,
        % pero recordamos que provienen del int16(round()) del ADC de Bob.
        Y_int16 = int16(Y(:, blk)); 
        
        % Formateamos como un bus gigante de 128 bits (8 variables x 16 bits)
        % Orden: Y8 Y7 Y6 Y5 Y4 Y3 Y2 Y1 (Endianness para SystemVerilog)
        bin_str = '';
        for dim = 8:-1:1
            % Aseguramos formato complemento a 2 sin signo para dec2hex
            hex_val = dec2hex(typecast(Y_int16(dim), 'uint16'), 4); 
            bin_str = [bin_str, hex_val];
        end
        fprintf(fid_mdr_in, '%s\n', bin_str);
    end
    fclose(fid_mdr_in);
    disp('   -> Archivo de entradas generado con éxito.');

    % =====================================================================
    % Exportar Datos Crudos (ADC) para el DSP en FPGA
    % Cuantizamos a 16 bits la señal cruda con el ruido de fase INCLUIDO
    % =====================================================================
    P_ADC = int16(round(P_B_rx));
    Q_ADC = int16(round(Q_B_rx));

    fid_adc = fopen(fullfile(DATA_DIR, 'bob_raw_adc.txt'), 'w');
    % Guardamos los 52.224 + pilotos (N_FIBER)
    for i=1:N_FIBER
        fprintf(fid_adc, '%04X%04X\n', typecast(Q_ADC(i), 'uint16'), typecast(P_ADC(i), 'uint16'));
    end
    fclose(fid_adc);

    % Alice full 26112 symbols (for MDR RX verification)
    fid_alice_full = fopen(fullfile(DATA_DIR, 'alice_full_data.txt'), 'w');
    for i=1:N_BOB_DATA
        fprintf(fid_alice_full, '%04X%04X\n', typecast(Q_A_int(i), 'uint16'), typecast(P_A_int(i), 'uint16'));
    end
    fclose(fid_alice_full);
   % =====================================================================
    % Bob random bits (Empaquetado: 8 bits por línea para TB)
    % =====================================================================
    fid_rand = fopen(fullfile(DATA_DIR, 'bob_random_bits.txt'), 'w');
    for blk = 1:N_bloques
        bits_blk = bits_bob_all(:, blk);
        bin_str = '';
        % Orden Endianness SystemVerilog: [dim 8] ... [dim 1]
        for dim = 8:-1:1
            bin_str = [bin_str, num2str(bits_blk(dim))];
        end
        fprintf(fid_rand, '%s\n', bin_str);
    end
    fclose(fid_rand);

    % =====================================================================
    % Expected public messages m_i (Empaquetado: 256 bits = 8 x 32b por línea)
    % =====================================================================
    fid_m = fopen(fullfile(DATA_DIR, 'expected_m_messages.txt'), 'w');
    for blk = 1:N_bloques
        Y_i = Y(:, blk);
        Y_norm = Y_i / norm(Y_i);
        M_Y = generar_matriz_ortogonal(Y_norm);
        m_i = M_Y' * (1 - 2*bits_bob_all(:, blk));
        
        hex_str_line = '';
        for dim = 8:-1:1
            % CAMBIO VITAL: Formato Q24 en lugar de Q31 para cuadrar con FPGA
            m_q24 = int32(round(m_i(dim) * 2^24));
            hex_str_line = [hex_str_line, dec2hex(typecast(m_q24, 'uint32'), 8)];
        end
        fprintf(fid_m, '%s\n', hex_str_line);
    end
    fclose(fid_m);
    % Expected LLR results (for MDR RX verification)
    fid_llr = fopen(fullfile(DATA_DIR, 'expected_llr_results.txt'), 'w');
    for blk = 1:N_bloques
        for dim = 1:N_dimensiones
            llr_fp = int32(round(LLR_all(dim, blk) * 2^31));
            fprintf(fid_llr, '%08X\n', typecast(llr_fp, 'uint32'));
        end
    end
    fclose(fid_llr);
    % =====================================================================
    % Exportar Síndrome esperado para el Testbench del LDPC Decoder
    % =====================================================================
    S_matrix = reshape(syndrome_1, Z, mb).';
    
    fid_syn = fopen(fullfile(DATA_DIR, 'expected_syndrome.txt'), 'w');
    for i = 1:mb
        % ¡AQUÍ ESTÁ LA MAGIA! Iteramos al revés para que SystemVerilog
        % asigne el CNU 0 al bit 0 correctamente.
        fprintf(fid_syn, '%d', S_matrix(i, Z:-1:1));
        fprintf(fid_syn, '\n'); 
    end
    fclose(fid_syn);
    disp('   -> expected_syndrome.txt generado con éxito (Endianness corregido).');
    % =====================================================================
    % Exportar LLRs (u_bits.txt) en formato Signo-Magnitud 8-bits
    % para la L_BRAM del Testbench SystemVerilog
    % =====================================================================
    % llr_ch tiene tamaño (68 * 384) x 1. Lo pasamos a matriz 68 x 384.
    llr_ch_matrix = reshape(llr_ch, Z, nb).'; 
    
    fid_ubits = fopen(fullfile(DATA_DIR, 'u_bits.txt'), 'w');
    
    for c = 1:nb
        line_str = '';
        % Iteramos al revés (Z bajando a 1) porque en SystemVerilog
        % L_read[0] se conecta a los bits [7:0] (la extrema derecha del string)
        for z = Z:-1:1
            % 1. Redondear al entero más cercano
            val = round(llr_ch_matrix(c, z));
            
            % 2. Saturación a los límites de 7 bits de magnitud (+/- 127)
            if val > 127,  val = 127;  end
            if val < -127, val = -127; end
            
            % 3. Conversión a Signo-Magnitud
            if val < 0
                sign_b = 1;
                mag_b  = -val;
            else
                sign_b = 0;
                mag_b  = val;
            end
            
            % 4. Formatear como 8 bits binarios: [1 bit signo][7 bits magnitud]
            % (sign_b * 128 coloca el bit de signo en el MSB)
            bin_val = sign_b * 128 + mag_b;
            bin_str = dec2bin(bin_val, 8);
            
            % 5. Concatenar a la línea
            line_str = [line_str, bin_str];
        end
        % Escribir la línea de 3072 caracteres en el archivo
        fprintf(fid_ubits, '%s\n', line_str);
    end
    fclose(fid_ubits);
    disp('   -> u_bits.txt generado con éxito (68 líneas x 3072 bits).');
    % =====================================================================
    % EXPORTAR VERDAD ABSOLUTA PARA EL AUTO-CHECKER (Todas las 46 filas)
    % Usa L_write_history capturado durante la decodificación layered,
    % que refleja exactamente lo que el hardware escribe en cada edge.
    % =====================================================================
    disp('   -> Exportando expected_L_write_all.txt para Vivado (316 edges)...');

    fid_l_write = fopen(fullfile(DATA_DIR, 'expected_L_write_all.txt'), 'w');

    for edge_idx = 1:length(L_write_history)
        L_write_block = L_write_history{edge_idx};

        % Formateo a 8 bits Signo-Magnitud y ordenamiento Endianness (Z bajando a 1)
        bin_str = '';
        for z = Z:-1:1
            val = L_write_block(z);

            % Saturación hardware
            if val > 127, val = 127; end
            if val < -127, val = -127; end

            % Conversión a Signo-Magnitud
            if val < 0
                sm_val = 128 + abs(val);
            else
                sm_val = val;
            end

            % Concatenar en binario
            bin_str = [bin_str, dec2bin(sm_val, 8)];
        end

        fprintf(fid_l_write, '%s\n', bin_str);
    end

    fclose(fid_l_write);
    fprintf('   -> expected_L_write_all.txt generado (%d edges).\n', length(L_write_history));
end

disp('======================================================');
disp('--- PEGA ESTO EN MDR_ALICE_DATAPATH.SV ---');
disp('======================================================');

% Inyectamos un vector de prueba (1 a 8) para extraer el ADN de tu matriz
X_dummy = (1:8)'; 
M_X = generar_matriz_ortogonal(X_dummy);

% Extraemos los índices (restamos 1 porque SystemVerilog empieza en 0)
M_IDX = abs(M_X) - 1;

% Extraemos los signos (1 si es negativo, 0 si es positivo)
M_NEG = M_X < 0;

% 1. Imprimir M_IDX
fprintf('localparam int M_IDX [0:7][0:7] = ''{\n');
for r = 1:8
    fprintf('    ''{%d, %d, %d, %d, %d, %d, %d, %d}', M_IDX(r,:));
    if r < 8, fprintf(','); end
    fprintf('\n');
end
fprintf('};\n\n');

% 2. Imprimir M_NEG
fprintf('localparam logic M_NEG [0:7][0:7] = ''{\n');
for r = 1:8
    fprintf('    ''{%d, %d, %d, %d, %d, %d, %d, %d}', M_NEG(r,:));
    if r < 8, fprintf(','); end
    fprintf('\n');
end
fprintf('};\n');
disp('======================================================');

disp('======================================================');
disp('--- PEGA ESTE CÓDIGO EN mdr_alice_datapath.sv ---');
disp('======================================================');

% Inyectamos un vector de prueba para extraer el ADN de TU matriz exacta
X_dummy = (1:8)'; 
M_X = generar_matriz_ortogonal(X_dummy);

% Extraemos los índices (restamos 1 porque SystemVerilog empieza en 0)
M_IDX = abs(M_X) - 1;

% Extraemos los signos (1 si es negativo, 0 si es positivo)
M_NEG = M_X < 0;

% 1. Imprimir M_IDX
fprintf('localparam int M_IDX [0:7][0:7] = ''{\n');
for r = 1:8
    fprintf('    ''{%d, %d, %d, %d, %d, %d, %d, %d}', M_IDX(r,:));
    if r < 8, fprintf(','); end
    fprintf('\n');
end
fprintf('};\n\n');

% 2. Imprimir M_NEG
fprintf('localparam logic M_NEG [0:7][0:7] = ''{\n');
for r = 1:8
    fprintf('    ''{%d, %d, %d, %d, %d, %d, %d, %d}', M_NEG(r,:));
    if r < 8, fprintf(','); end
    fprintf('\n');
end
fprintf('};\n');
disp('======================================================');