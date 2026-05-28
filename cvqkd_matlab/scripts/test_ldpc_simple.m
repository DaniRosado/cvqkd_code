%% TEST_LDPC_SIMPLE - Prueba básica del decoder LDPC con datos conocidos
%
% Este test verifica si el decoder LDPC funciona con un ejemplo simple

clear; clc;

fprintf('========================================\n');
fprintf(' Test Simple de LDPC Decoder\n');
fprintf('========================================\n\n');

%% 1. Cargar matriz H
fprintf('[1/4] Cargando matriz LDPC...\n');
SCRIPT_DIR = fileparts(mfilename('fullpath'));
PROJ_DIR = fileparts(SCRIPT_DIR);
CODE_DIR = fileparts(PROJ_DIR);
BOB_DIR = fullfile(CODE_DIR, 'cvqkd_bob');

bg_matrix = load(fullfile(BOB_DIR, 'NR_1_1_384.txt'));
[mb, nb] = size(bg_matrix);
Z = 384;

% Construir H
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

fprintf('  Matriz H: %d × %d\n', size(H,1), size(H,2));
fprintf('  Checks: %d, Variables: %d\n\n', mb*Z, nb*Z);

%% 2. Generar mensaje aleatorio y síndrome
fprintf('[2/4] Generando mensaje de prueba...\n');
bits_true = randi([0 1], nb*Z, 1);
syndrome_target = mod(H * double(bits_true), 2);
active_checks = sum(syndrome_target);

fprintf('  Bits generados: %d\n', length(bits_true));
fprintf('  Síndrome activo: %d checks de %d (%.2f%%)\n\n', ...
    active_checks, length(syndrome_target), 100*active_checks/length(syndrome_target));

%% 3. Crear LLRs con ruido
fprintf('[3/4] Creando LLRs con ruido...\n');
SNR_db = 3.0;  % SNR moderado
SNR_linear = 10^(SNR_db/10);
sigma_noise = 1/sqrt(2*SNR_linear);

% LLR = log(P(bit=0|y) / P(bit=1|y)) ≈ (2/σ²) * y
% donde y = x + n, x = +1 para bit=0, x = -1 para bit=1
llr_scale = 2 / (sigma_noise^2);
bits_mapped = 1 - 2*bits_true;  % 0→+1, 1→-1
received = bits_mapped + sigma_noise * randn(size(bits_mapped));
llr_ch = llr_scale * received;

% Bits estimados sin decoder
bits_no_decode = (llr_ch < 0);
ber_no_decode = sum(bits_no_decode ~= bits_true) / length(bits_true);

fprintf('  SNR: %.1f dB\n', SNR_db);
fprintf('  BER sin decoder: %.4f (%.2f%%)\n\n', ber_no_decode, ber_no_decode*100);

%% 4. Decodificar con Min-Sum
fprintf('[4/4] Decodificando con Scaled Min-Sum...\n');

alpha = 0.75;
max_iter = 50;

% Construir listas de vecinos
[rows_h, cols_h] = find(H);
num_edges = length(rows_h);
cn_edges = cell(mb*Z, 1);
vn_edges = cell(nb*Z, 1);
for e = 1:num_edges
    cn_edges{rows_h(e)}(end+1) = e;
    vn_edges{cols_h(e)}(end+1) = e;
end

% Mensajes
msg_v2c = zeros(num_edges, 1);
msg_c2v = zeros(num_edges, 1);

% Inicializar
for v = 1:nb*Z
    edges_v = vn_edges{v};
    if ~isempty(edges_v)
        msg_v2c(edges_v) = llr_ch(v);
    end
end

converged = false;
for iter = 1:max_iter
    % CN update
    for c = 1:mb*Z
        edges_c = cn_edges{c};
        if isempty(edges_c), continue; end

        msgs = msg_v2c(edges_c);
        abs_vals = abs(msgs);
        sign_vals = sign(msgs);
        sign_vals(sign_vals == 0) = 1;

        % Min1 y min2
        [sorted_abs, idx_sort] = sort(abs_vals);
        min1 = sorted_abs(1);
        min2 = sorted_abs(min(2, length(sorted_abs)));

        % Signo con síndrome
        syndrome_sign = 1 - 2*syndrome_target(c);
        sign_prod = prod(sign_vals) * syndrome_sign;

        % Mensajes extrinsecos
        for k = 1:length(edges_c)
            if abs_vals(k) == min1
                min_use = min2;
            else
                min_use = min1;
            end
            sign_excl = sign_prod * sign_vals(k);
            msg_c2v(edges_c(k)) = alpha * sign_excl * min_use;
        end
    end

    % VN update
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

    % Hard decision
    bits_est = (llr_post < 0);
    syndrome_est = mod(H * double(bits_est), 2);

    % Verificación
    if all(syndrome_est == syndrome_target)
        converged = true;
        fprintf('  [✓] Convergió en iteración %d\n', iter);
        break;
    end

    if mod(iter, 10) == 0
        ber_current = sum(bits_est ~= bits_true) / length(bits_true);
        unsat = sum(syndrome_est ~= syndrome_target);
        fprintf('    Iter %d: BER = %.4f, Checks no sat = %d\n', ...
            iter, ber_current, unsat);
    end
end

% Resultado final
bits_decoded = (llr_post < 0);
ber_decoded = sum(bits_decoded ~= bits_true) / length(bits_true);

fprintf('\n========================================\n');
fprintf(' RESULTADOS\n');
fprintf('========================================\n');
fprintf('BER sin decoder:    %.6f\n', ber_no_decode);
fprintf('BER con decoder:    %.6f\n', ber_decoded);
fprintf('Mejora:             %.2fx\n', ber_no_decode / (ber_decoded + eps));
fprintf('Convergencia:       %s\n', iif(converged, 'SÍ', 'NO'));
fprintf('========================================\n\n');

if ber_decoded < ber_no_decode * 0.1
    fprintf('[✓] LDPC FUNCIONA CORRECTAMENTE\n');
    fprintf('El decoder redujo el BER significativamente.\n\n');
elseif ber_decoded < ber_no_decode
    fprintf('[~] LDPC FUNCIONA PARCIALMENTE\n');
    fprintf('El decoder reduce errores pero no lo suficiente.\n');
    fprintf('Puede necesitar más iteraciones o mejor SNR.\n\n');
else
    fprintf('[✗] LDPC NO FUNCIONA\n');
    fprintf('El decoder NO está reduciendo errores.\n');
    fprintf('Hay un bug en el algoritmo o en los datos de entrada.\n\n');
end

function out = iif(cond, true_val, false_val)
    if cond
        out = true_val;
    else
        out = false_val;
    end
end
