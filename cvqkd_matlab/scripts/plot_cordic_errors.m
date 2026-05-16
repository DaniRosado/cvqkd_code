% Script para graficar los errores masivos del CORDIC de rotación
%clear; clc; close all;

% 1. Cargar el archivo de errores
disp('Cargando cordic_rot_errors.txt...');
data = load('C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/cordic_rot_errors.txt');

% Columnas: [Índice, Fase Inyectada, Diff_P, Diff_Q, Exp_P, Exp_Q, Out_P, Out_Q]
out_idx   = data(:, 1);
phase_raw = data(:, 2);
diff_p    = data(:, 3);
diff_q    = data(:, 4);

% Convertir la fase de formato 3Q15 a radianes
fase_rad = phase_raw / 32768.0;

% Calcular la magnitud del error
error_mag = sqrt(double(diff_p).^2 + double(diff_q).^2);

% Identificar las muestras con error significativo (error > 1 por cuantización)
idx_error = find(error_mag > 1.5);
idx_ok    = find(error_mag <= 1.5);

disp(['Total de muestras: ', num2str(length(out_idx))]);
disp(['Muestras con error: ', num2str(length(idx_error))]);

% Calcular la magnitud del vector de entrada esperado (tamaño del vector)
exp_p = data(:, 5); exp_q = data(:, 6);
input_mag = sqrt(double(exp_p).^2 + double(exp_q).^2);

% =========================================================================
% GRAFICAS
% =========================================================================
figure('Name', 'Analisis de Errores del CORDIC', 'NumberTitle', 'off', 'Position', [50, 50, 1400, 800]);

% 1. Error vs Índice de Muestra
subplot(2, 3, 1);
plot(out_idx, diff_p, 'r.', 'DisplayName', 'Error P', 'MarkerSize', 5); hold on;
plot(out_idx, diff_q, 'b.', 'DisplayName', 'Error Q', 'MarkerSize', 5);
title('Error vs Índice de Muestra');
xlabel('Muestra'); ylabel('Diferencia (Bits)');
legend; grid on;

% 2. Error Magnitud vs Fase Inyectada (EL GRÁFICO CLAVE)
subplot(2, 3, 2);
scatter(fase_rad(idx_ok), error_mag(idx_ok), 10, 'g', 'filled', 'DisplayName', 'OK'); hold on;
scatter(fase_rad(idx_error), error_mag(idx_error), 10, 'r', 'filled', 'DisplayName', 'Error');
title('Magnitud del Error vs Ángulo de Fase');
xlabel('Fase Inyectada (Radianes)'); ylabel('Magnitud del Error');
legend; grid on;
xlim([-pi, pi]);

% 3. Histograma de la Fase en Muestras con Error
% Esto nos dirá si los errores ocurren en un cuadrante específico
subplot(2, 3, 3);
if ~isempty(idx_error)
    histogram(fase_rad(idx_error), 50, 'FaceColor', 'r');
    title('Fases que provocan error');
    xlabel('Fase Inyectada (Radianes)'); ylabel('Frecuencia');
    xlim([-pi, pi]);
else
    title('¡No hay errores!');
end
grid on;

% 4. Salida Esperada en Plano Complejo (dónde cae el dato)
subplot(2, 3, 4);
scatter(exp_p(idx_ok), exp_q(idx_ok), 5, 'g', 'filled', 'DisplayName', 'OK'); hold on;
scatter(exp_p(idx_error), exp_q(idx_error), 5, 'r', 'filled', 'DisplayName', 'Error');
title('Constelación Esperada (Rojo = Falló el CORDIC)');
xlabel('P Esperado'); ylabel('Q Esperado');
legend; grid on; axis equal;

% 5. Magnitud del Error vs Tamaño del Vector de Entrada
subplot(2, 3, 5);
scatter(input_mag(idx_ok), error_mag(idx_ok), 5, 'g', 'filled', 'DisplayName', 'OK'); hold on;
scatter(input_mag(idx_error), error_mag(idx_error), 5, 'r', 'filled', 'DisplayName', 'Error');
title('Error vs Magnitud del Vector Entrada');
xlabel('Magnitud del Vector (Bits)'); ylabel('Magnitud del Error');
legend; grid on;

% 6. Histograma del Tamaño de Vector en Muestras con Error
subplot(2, 3, 6);
if ~isempty(idx_error)
    histogram(input_mag(idx_error), 50, 'FaceColor', 'r');
    title('Tamaños de vector que fallan');
    xlabel('Magnitud del Vector'); ylabel('Frecuencia');
else
    title('¡No hay errores!');
end
grid on;

% =========================================================================
% FIGURA 2: ESTILO CLÁSICO DEL DSP
% =========================================================================
figure('Name', 'Error de Fase y Cuantización: Vivado vs MATLAB', 'NumberTitle', 'off', 'Position', [150, 150, 1000, 700]);

% 1. Error Individual de Cuadraturas
subplot(2, 1, 1);
plot(out_idx, diff_q, 'b', 'DisplayName', 'Error en Q'); hold on;
plot(out_idx, diff_p, 'r', 'DisplayName', 'Error en P');
title('Error Individual de Cuadraturas (Vivado - MATLAB)');
xlabel('Número de Muestra Útil'); ylabel('Error de Amplitud (Bits ADC)');
legend; grid on;

% 2. Magnitud Media del Error
error_medio = (abs(diff_p) + abs(diff_q)) / 2;
subplot(2, 1, 2);
plot(out_idx, error_medio, 'k');
title('Magnitud Media del Error (|Err\_Q| + |Err\_P|) / 2');
xlabel('Número de Muestra Útil'); ylabel('Error Medio (Bits)');
grid on;
