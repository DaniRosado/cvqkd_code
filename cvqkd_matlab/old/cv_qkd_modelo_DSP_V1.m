%% ========================================================================
% GOLDEN MODEL: Recuperador de Fase CV-QKD (Trama 1 de 16, ADC 16 bits)
% VERSIÓN CORREGIDA: Pilotos In-Phase y corrección de gráfica
% ========================================================================
%clear; clc; close all;

%% 1. PARÁMETROS DEL SISTEMA Y FORMATO
N_tramas = 100;                 % Número de tramas a simular
L_trama  = 16;         
% Longitud de la trama (1 Piloto + 15 Datos)
N_muestras = N_tramas * L_trama + 1;

% Formatos Fixed-Point (Punto fijo)
bits_frac = 15;                 % Q1.15 para el ADC (16 bits)
escala_q1_15 = 2^bits_frac;

% Parámetros del CORDIC (IP de Vivado)
%Esta ganancia cambia a si que hay que tener cuidado, en nuestros CORDICs
%son más ceracnas al 0.8
cordic_gain = 1.64676;          % Estiramiento natural del CORDIC
cordic_comp = 1 / cordic_gain;  % Multiplicador para normalizar (aprox 0.607)

%% 2. GENERACIÓN DE SEÑAL DE ENTRADA (Emulando a Alice y el Canal)
% a) Generamos datos cuánticos de muy baja amplitud (ruido Gaussiano)
% -> descomentar para generar datos nuevos
%p_tx = randn(N_muestras, 1) * 0.05;
%q_tx = randn(N_muestras, 1) * 0.05;

% b) Insertamos pulsos Piloto cada 16 muestras
idx_pilotos = 1:L_trama:N_muestras;
% TRUCO HARDWARE: Enviamos el piloto solo por P. Su ángulo base será 0 rad.
p_tx(idx_pilotos) = 0.8;  
q_tx(idx_pilotos) = 0.0; 

% c) Emulamos la deriva de fase del canal de fibra
fase_canal = 0.5 * sin(2*pi * (1:N_muestras)' / 500); 

% Aplicamos la rotación del canal
p_rx = p_tx .* cos(fase_canal) - q_tx .* sin(fase_canal);
q_rx = p_tx .* sin(fase_canal) + q_tx .* cos(fase_canal);

%% 3. EL GOLDEN MODEL (Lo que hace la FPGA de Bob)
% a) Cuantización del ADC (Forzamos a Q1.15)
p_rx_q = max(min(round(p_rx * escala_q1_15) / escala_q1_15, 1 - 1/escala_q1_15), -1);
q_rx_q = max(min(round(q_rx * escala_q1_15) / escala_q1_15, 1 - 1/escala_q1_15), -1);

% Inicializamos vectores de salida
p_out = zeros(N_muestras, 1);
q_out = zeros(N_muestras, 1);
fase_recuperada = zeros(N_muestras, 1);

% b) Procesamiento Trama a Trama
for k = 1:(N_tramas)
    idx_A = (k-1)*L_trama + 1;       % Piloto A
    idx_B = idx_A + L_trama;         % Piloto B
    idx_datos = (idx_A + 1):(idx_B - 1); % Los 15 datos
    
    % CORDIC 1 (VECT)
    theta_A = atan2(q_rx_q(idx_A), p_rx_q(idx_A));
    theta_B = atan2(q_rx_q(idx_B), p_rx_q(idx_B));
    
    % Evitamos que la gráfica caiga a cero guardando el ángulo en el piloto
    fase_recuperada(idx_A) = theta_A;
    if k == (N_tramas - 1)
        fase_recuperada(idx_B) = theta_B;
    end
    
    % DIFERENCIA Y DIVISIÓN (shift >> 4)
    diferencia = angdiff(theta_A, theta_B); 
    delta_theta = diferencia / 16; 
    
    % ACUMULADOR Y CORDIC 2 (ROT)
    theta_acumulado = theta_A;
    
    for i = 1:15
        idx_actual = idx_datos(i);
        theta_acumulado = theta_acumulado + delta_theta;
        fase_recuperada(idx_actual) = theta_acumulado;
        
        % CORDIC ROT: Deshacemos la fase
        p_rot = cordic_gain * (p_rx_q(idx_actual) * cos(-theta_acumulado) - q_rx_q(idx_actual) * sin(-theta_acumulado));
        q_rot = cordic_gain * (p_rx_q(idx_actual) * sin(-theta_acumulado) + q_rx_q(idx_actual) * cos(-theta_acumulado));
        
        % COMPENSACIÓN Y TRUNCADO
        p_norm = p_rot * cordic_comp;
        q_norm = q_rot * cordic_comp;
        
        p_out(idx_actual) = round(p_norm * escala_q1_15) / escala_q1_15;
        q_out(idx_actual) = round(q_norm * escala_q1_15) / escala_q1_15;
    end
end

%% 4. EXPORTACIÓN DE VECTORES DE TEST PARA VIVADO
P_IN_HEX  = typecast(int16(p_rx_q * escala_q1_15), 'uint16');
Q_IN_HEX  = typecast(int16(q_rx_q * escala_q1_15), 'uint16');
P_OUT_HEX = typecast(int16(p_out * escala_q1_15), 'uint16');
Q_OUT_HEX = typecast(int16(q_out * escala_q1_15), 'uint16');

fid_in = fopen('input_vectors.txt', 'w');
fid_out = fopen('expected_outputs.txt', 'w');

for i = 1:N_muestras
    fprintf(fid_in, '%04X%04X\n', Q_IN_HEX(i), P_IN_HEX(i));
    fprintf(fid_out, '%04X%04X\n', Q_OUT_HEX(i), P_OUT_HEX(i));
end

fclose(fid_in); fclose(fid_out);

%% 5. VISUALIZACIÓN DE RESULTADOS
figure('Name', 'Recuperación de Fase CV-QKD');
subplot(2,1,1);
plot(fase_canal, 'r', 'LineWidth', 1.5); hold on;
plot(fase_recuperada, 'b--', 'LineWidth', 1.5);
title('Tracking de Fase');
legend('Fase del Canal (Deriva)', 'Fase Recuperada (Interpolada)');
xlabel('Muestras'); ylabel('Radianes');

subplot(2,1,2);
plot(p_tx(2:16), q_tx(2:16), 'go'); hold on;
plot(p_out(2:16), q_out(2:16), 'bx', 'MarkerSize', 8);
title('Constelación de Datos (Trama 1)');
legend('TX Original (Alice)', 'RX Corregido (Bob)');
xlabel('P (Cuadratura)'); ylabel('Q (Cuadratura)');
grid on; axis equal;

% === LECTURA DE LOS RESULTADOS DE VIVADO ===
fid_sim = fopen('C:\Users\usser\Vivado_Sources\cvqkd_bob\Sim\sim_outputs.txt', 'r');
sim_data = fscanf(fid_sim, '%8x');
fclose(fid_sim);

% Extraer Q y P (16 bits cada uno)
q_sim_hex = bitshift(sim_data, -16);
p_sim_hex = bitand(sim_data, 65535);

% Convertir de complemento a 2 (Q1.15) a decimal flotante
q_sim = double(typecast(uint16(q_sim_hex), 'int16')) / 2^15;
p_sim = double(typecast(uint16(p_sim_hex), 'int16')) / 2^15;
% === GRÁFICA COMPARATIVA FINAL ===

% 1. Purgar los huecos de los pilotos en el Golden Model
% Copiamos el array y eliminamos las posiciones 1, 17, 33...
p_out_solo_datos = p_out;
p_out_solo_datos(1:16:end) = []; 

q_out_solo_datos = q_out;
q_out_solo_datos(1:16:end) = []; 
    
% 2. Comprobación de seguridad (Ambos deberían medir 1500)
disp(['Muestras de MATLAB (solo datos): ', num2str(length(p_out_solo_datos))]);
disp(['Muestras de Vivado: ', num2str(length(p_sim))]);

% 3. Dibujar
figure;
plot(q_out_solo_datos, 'b', 'LineWidth', 2); hold on; 
plot(q_sim, 'r--', 'LineWidth', 1.5);           
title('Validación Hardware vs Software (Solo Datos útiles)');
legend('Golden Model (MATLAB)', 'Hardware (Vivado)');
grid on;