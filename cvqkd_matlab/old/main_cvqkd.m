function main_cvqkd()
    % =====================================================================
    % SIMULACIÓN CV-QKD GG02: Detección Heterodina & Reconciliación Inversa
    % =====================================================================
    clc; clear; close all;
    
    %% 1. CONFIGURACIÓN DE PARÁMETROS
    fprintf('=== INICIANDO SIMULACIÓN CV-QKD ===\n');
    
    % Parámetros Físicos
    cfg.Va = 3;             % Varianza de modulación de Alice (desviación típica = 3)
    cfg.T_channel = 0.5;    % Transmisividad del canal (0.5 = 3dB de pérdidas)
    cfg.noise_excess = 0.01;% Ruido en exceso (en unidades de ruido de disparo - SNU)
    cfg.noise_vac = 1;      % Ruido de vacío (normalizado a 1)
    
    % Parámetros LDPC
    cfg.n = 65536;          % Tamaño de bloque (bits)
    cfg.rate = 0.1;         % Tasa del código (R = k/n)
    cfg.max_iter = 50;      % Iteraciones del decodificador BP
    
    % Generar Matriz LDPC (H)
    % Nota: Generamos una matriz dispersa aleatoria para la simulación.
    % En producción, usar matrices QC-LDPC estandarizadas (ej. DVB-S2 o 802.11).
    fprintf('-> Generando matriz de paridad LDPC (N=%d, R=%.1f)...\n', cfg.n, cfg.rate);
    H = generate_ldpc_matrix(cfg.n, cfg.rate);
    
    %% 2. GENERACIÓN DE ESTADOS EN ALICE (GG02)
    fprintf('-> Alice: Generando variables gaussianas...\n');
    % Generamos 2 bloques de tamaño n (uno para X, otro para P)
    % Sin embargo, para la clave final solemos concatenar o usar una cuadratura.
    % Aquí simularemos la clave sobre la cuadratura X para simplificar la visualización,
    % pero el código genera ambas.
    
    [Xa, Pa] = generate_alice_states(cfg.n, cfg.Va);
    
    % Cuantización de Alice (Solo para referencia interna, no usada en reconciliación inversa)
    Ka_ref = quantize_sign(Xa); 
    
    %% 3. TRANSMISIÓN POR EL CANAL CUÁNTICO (AWGN)
    fprintf('-> Canal: Transmisión con T=%.2f y Ruido...\n', cfg.T_channel);
    
    % Ruido total = Ruido Vacío + Ruido Exceso
    % En detección heterodina, el ruido de vacío entra por el puerto no usado del BS.
    noise_total_var = cfg.noise_vac + cfg.noise_excess; 
    
    [Xb, Pb] = quantum_channel(Xa, Pa, cfg.T_channel, noise_total_var);
    
    %% 4. GENERACIÓN DE CLAVE DE BOB Y SÍNDROME
    fprintf('-> Bob: Cuantización y cálculo de Síndrome...\n');
    
    % Bob cuantiza sus mediciones (Xb) para crear SU clave (Target Key)
    Kb = quantize_sign(Xb); % Clave binaria de Bob (vector columna)
    
    % Calcular Síndrome S = H * Kb (aritmética GF(2))
    % Convertimos a double para operar y luego mod 2
    syndrome = mod(H * double(Kb), 2);
    
    % Hash de la clave de Bob para verificación final
    hash_Bob = calculate_hash(Kb);
    fprintf('   Hash Bob: %s\n', hash_Bob);
    
    %% 5. RECONCILIACIÓN INVERSA (ALICE ESTIMATES BOB)
    fprintf('-> Alice: Reconciliación Inversa (Decodificación de Síndrome)...\n');
    
    % Alice recibe 'syndrome' y usa sus datos 'Xa' para adivinar 'Kb'.
    % Paso 1: Calcular LLRs (Log-Likelihood Ratios) iniciales basados en Xa
    % Alice estima Xb a partir de Xa: E[Xb] = sqrt(T)*Xa
    mu_pred = sqrt(cfg.T_channel) * Xa;
    sigma_channel = sqrt(noise_total_var);
    
    % LLR = ln( P(bit=0|Xa) / P(bit=1|Xa) )
    % bit=0 si Xb >= 0. P(Xb >= 0) depende de la Gaussiana centrada en mu_pred.
    L_int = calculate_llr_gaussian(mu_pred, sigma_channel);
    
    % Paso 2: Decodificación Belief Propagation con Síndrome
    % Alice intenta recuperar Kb tal que H*Kb = syndrome
    Kb_est = ldpc_bp_syndrome_decode(L_int, syndrome, H, cfg.max_iter);
    
    %% 6. VERIFICACIÓN
    fprintf('-> Verificación de Claves...\n');
    
    hash_Alice = calculate_hash(Kb_est);
    fprintf('   Hash Alice (Estimado): %s\n', hash_Alice);
    
    % Calcular tasa de error de bit (BER) antes y después de corrección
    ber_raw = mean(Ka_ref ~= Kb); % Diferencia bruta entre Alice y Bob (física)
    ber_final = mean(Kb_est ~= Kb); % Diferencia tras corrección
    
    fprintf('\n=== RESULTADOS ===\n');
    fprintf('BER Físico (Raw): %.4f\n', ber_raw);
    fprintf('BER Final (Tras LDPC): %.4e\n', ber_final);
    
    if strcmp(hash_Alice, hash_Bob)
        fprintf('ESTADO: [EXITO] Las claves coinciden perfectamente.\n');
    else
        fprintf('ESTADO: [FALLO] La reconciliación falló.\n');
    end
end

%% ========================================================================
%% FUNCIONES AUXILIARES
%% ========================================================================

function [X, P] = generate_alice_states(n, sigma)
    % Genera variables gaussianas centradas en 0 con desviación sigma
    X = sigma * randn(n, 1);
    P = sigma * randn(n, 1);
end

function K = quantize_sign(Data)
    % Cuantización binaria por signo
    % 0 si Data >= 0
    % 1 si Data < 0
    K = zeros(size(Data));
    K(Data < 0) = 1;
end

function [Xb, Pb] = quantum_channel(Xa, Pa, T, noise_var)
    % Canal AWGN con pérdidas
    % Xb = sqrt(T)*Xa + N
    n = length(Xa);
    noise_std = sqrt(noise_var);
    
    Nx = noise_std * randn(n, 1);
    Np = noise_std * randn(n, 1);
    
    Xb = sqrt(T) * Xa + Nx;
    Pb = sqrt(T) * Pa + Np;
end

function LLR = calculate_llr_gaussian(mu, sigma)
    % Calcula LLR para una variable binaria generada por el signo de una
    % variable gaussiana.
    % LLR = ln( P(x>0) / P(x<0) )
    % P(x>0) = 1 - Q(mu/sigma) = Phi(mu/sigma)
    % Usamos la función error complementaria 'erfc' para precisión numérica
    
    % Argumento de la función Q
    z = mu ./ sigma;
    
    % P(bit=0) = P(val >= 0) = normcdf(z)
    % Para evitar problemas numéricos con logs de 0, acotamos probabilidades
    epsilon = 1e-15;
    p0 = 0.5 * erfc(-z / sqrt(2)); % Definición de CDF usando erfc
    
    p0 = max(min(p0, 1-epsilon), epsilon);
    p1 = 1 - p0;
    
    LLR = log(p0 ./ p1);
end

function H = generate_ldpc_matrix(n, rate)
    % Genera una matriz de paridad dispersa aleatoria (simplificada)
    % Para un sistema real, usar dvbs2ldpc o cargar matrices estándar.
    
    m = round(n * (1 - rate)); % Número de filas (check nodes)
    
    % Construcción dispersa: peso de columna fijo = 3 (común en LDPC)
    col_weight = 3;
    
    % Generamos índices aleatorios para los 1s
    % Esto no garantiza la ausencia de ciclos cortos (girth 4), pero
    % funciona para demostración.
    total_ones = n * col_weight;
    rows_idx = randi(m, total_ones, 1);
    cols_idx = repelem(1:n, col_weight)';
    
    % Aseguramos que no haya duplicados en (row, col)
    H = sparse(rows_idx, cols_idx, 1, m, n);
    
    % Asegurar que sea binaria
    H = spones(H);
end

function bits_dec = ldpc_bp_syndrome_decode(LLR_int, syndrome, H, max_iter)
    % Decodificador Belief Propagation (Sum-Product) modificado para SÍNDROME.
    % H: Matriz de paridad (MxN)
    % syndrome: Vector de síndrome recibido de Bob (Mx1)
    
    [m, n] = size(H);
    
    % Mensajes Variable -> Check (inicializados con LLR del canal)
    % Usamos formato disperso para eficiencia de memoria si n es grande
    % Pero para implementación clara, usaremos estructura de índices.
    
    [rows, cols] = find(H); % Índices de las aristas
    % Mvc: Mensaje Variable a Check
    % Mcv: Mensaje Check a Variable
    
    % Inicialización
    Mvc = LLR_int(cols); 
    
    % Pre-computar índices para vectorización (sparse indexing es lento en bucles)
    % Esta es una implementación simplificada. Para velocidad C++ mex es mejor.
    
    for iter = 1:max_iter
        % 1. Actualización Check Nodes (Horizontal Step)
        % Mcv = 2 * atanh( prod( tanh(Mvc/2) ) ) * (-1)^Syndrome
        
        % Truco numérico: Usar aproximación Min-Sum o tanh en log domain
        % Aquí usamos tanh directo (cuidado con desbordamientos, usar min-sum en prod)
        
        % Agrupar mensajes por Check Node
        % Matlab no tiene "accumarray" con producto, así que lo hacemos en logaritmos
        % o usamos un bucle eficiente sobre filas.
        
        % Opción vectorizada simple (lenta para 65k bits en matlab puro, pero clara):
        Mcv = zeros(size(Mvc));
        
        % Iterar sobre checks (botella de cuello en MATLAB puro)
        % Para optimizar, asumimos grado constante o usamos representaciones matriciales
        % Aquí usamos la aproximación Min-Sum para velocidad en demo:
        % sign(Mcv) = prod(sign(Mvc)) * (-1)^S
        % abs(Mcv) = min(abs(Mvc))
        
        % NOTA DE IMPLEMENTACIÓN:
        % Escribir un decodificador BP completo y rápido en un solo script
        % es complejo. Usaremos el objeto de Matlab si existe, pero
        % el objeto 'ldpcDecoder' no soporta síndrome arbitrario fácilmente.
        % A continuación, un BP simplificado "Min-Sum":
        
        % Convertir a estructura matricial dispersa para operaciones rápidas
        M_matrix = sparse(rows, cols, Mvc, m, n);
        
        % Paso Check (Min-Sum)
        % Encontrar min abs value por fila (excluyendo el propio mensaje)
        % Esto es costoso de codificar en pocas líneas.
        
        % ---> ESTRATEGIA ALTERNATIVA PARA SIMULACIÓN <---
        % Usaremos una decisión dura iterativa (Bit Flipping) si BP es muy complejo,
        % pero el usuario pidió BP. Implementaremos BP estándar vectorizado.
        
        % Tanh rule
        T = tanh(Mvc / 2);
        
        % Producto de T por filas (Check nodes)
        % Como es disperso, usamos un truco:
        % Prod_total_fila = prod(T_in_row)
        % T_out = Prod_total_fila / T_in
        
        % Calcular producto total por fila
        % Evitamos ceros numéricos
        T(T==0) = 1e-15; 
        
        % Log de magnitudes y signos para estabilidad
        log_abs_T = log(abs(T));
        sign_T = sign(T);
        
        sum_log = full(sparse(rows, cols, log_abs_T, m, n) * ones(n,1)); % Suma por filas
        prod_sign = full(sparse(rows, cols, sign_T, m, n) * ones(n,1));  % Prod signos (pseudo)
        % Corrección del prod_sign: sparse suma, pero necesitamos producto.
        % Producto de signos: (suma de (signo<0)) mod 2
        neg_count = full(sparse(rows, cols, double(sign_T < 0), m, n) * ones(n,1));
        row_sign = (-1).^neg_count;
        
        % Incorporar el SÍNDROME: Si S=1, invertimos el signo del check
        row_sign = row_sign .* ((-1).^syndrome);
        
        % Calcular mensaje saliente Mcv
        % Mcv_ij = 2 * atanh( (RowProd / T_ij) )
        
        % Expandir valores de fila a las aristas
        row_sum_log_expanded = sum_log(rows);
        row_sign_expanded = row_sign(rows);
        
        val_log = row_sum_log_expanded - log_abs_T;
        val_sign = row_sign_expanded .* sign_T; % Dividir signo es mult por signo
        
        T_new = val_sign .* exp(val_log);
        % Clipping para estabilidad de atanh
        T_new = max(min(T_new, 0.99999), -0.99999);
        Mcv = 2 * atanh(T_new);
        
        % 2. Actualización Variable Nodes (Vertical Step)
        % Mvc_j = LLR_int_j + sum(Mcv_inputs) - Mcv_input
        
        % Suma total de mensajes entrantes a cada variable
        col_sum = full(sparse(rows, cols, Mcv, m, n)' * ones(m,1)); % Suma por columnas
        
        % Restar el mensaje propio para obtener extrínseco
        col_sum_expanded = col_sum(cols);
        Mvc = LLR_int(cols) + col_sum_expanded - Mcv;
        
        % 3. Decisión Dura y Comprobación
        L_total = LLR_int + col_sum; % LLR posterior
        bits_est = double(L_total < 0); % 0 si L>0, 1 si L<0
        
        curr_syndrome = mod(H * bits_est, 2);
        if all(curr_syndrome == syndrome)
            % Convergencia lograda
            bits_dec = bits_est;
            return;
        end
    end
    
    % Si termina iteraciones
    bits_dec = double((LLR_int + col_sum) < 0);
end

function h_str = calculate_hash(bits)
    % Calcula hash MD5 simple para verificación
    % Requiere Java bridge (estándar en MATLAB)
    import java.security.*;
    import java.math.*;
    
    % Convertir bits a bytes (padding con ceros si es necesario)
    % Para simplificar, hasheamos la cadena de caracteres '0'/'1'
    bit_str = char(bits + '0')'; % Transponer para fila
    
    md = MessageDigest.getInstance('MD5');
    hash_bytes = md.digest(double(bit_str));
    
    % Convertir a Hex
    bi = BigInteger(1, hash_bytes);
    h_str = char(bi.toString(16));
end