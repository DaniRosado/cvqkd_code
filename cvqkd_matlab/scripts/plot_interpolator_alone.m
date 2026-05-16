% Script para comparar la fase interpolada AISLADA del FPGA frente al Ideal
%clear; clc; close all;

disp('Cargando sim_interpolator_alone.txt...');
data = load('C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/sim_interpolator_alone.txt');

% Columnas: [fase_datos_count, fase_vivado, fase_matlab]
idx         = data(:, 1);
fase_vivado = data(:, 2) / 32768.0; % Convertir de 3Q15 a radianes
fase_matlab = data(:, 3) / 32768.0; % Convertir de 3Q15 a radianes

% Gráfica 1: Seguimiento Completo
figure('Name', 'Tracking de Fase AISLADO', 'NumberTitle', 'off', 'Position', [150, 150, 1200, 600]);

plot(idx, fase_matlab, 'r-', 'LineWidth', 2, 'DisplayName', 'Ideal (MATLAB)'); hold on;
plot(idx, fase_vivado, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Interpolador Aislado (Vivado)');

title('Evolución de la Fase Interpolada Aislada (Vivado vs MATLAB)');
xlabel('Número de Dato Útil');
ylabel('Fase (Radianes)');
legend;
grid on;
ylim([-4, 4]);

% Gráfica 2: Error
figure('Name', 'Error de Interpolación Aislada', 'NumberTitle', 'off', 'Position', [200, 200, 1200, 400]);

error_fase_bruto = fase_vivado - fase_matlab;
error_fase_real = angle(exp(1j * error_fase_bruto));

plot(idx, error_fase_real, 'k');
title('Error Real de Interpolación Aislada (Físico)');
xlabel('Número de Dato Útil');
ylabel('Error (Radianes)');
ylim([-0.05, 0.05]);
grid on;

% Buscamos índices donde el error sea significativo (> 0.1 radianes)
% y generamos una gráfica interactiva (stem plot) enfocada en los errores
bad_idx = find(abs(error_fase_real) > 0.1);

if ~isempty(bad_idx)
    fprintf('\n¡ATENCIÓN! Se han detectado %d muestras con un error superior a 0.1 radianes.\n', length(bad_idx));
    fprintf('Generando visor detallado de los errores...\n');
    
    figure('Name', 'Visor de Errores Detallado', 'NumberTitle', 'off', 'Position', [250, 250, 1200, 500]);
    
    % Graficar las diferencias puntuales en forma de "stem" (agujas)
    stem(idx(bad_idx), error_fase_real(bad_idx), 'k', 'Marker', 'none'); hold on;
    plot(idx(bad_idx), fase_vivado(bad_idx), 'b.', 'MarkerSize', 15, 'DisplayName', 'Vivado (Fallo)');
    plot(idx(bad_idx), fase_matlab(bad_idx), 'ro', 'MarkerSize', 8, 'DisplayName', 'MATLAB (Ideal)');
    
    title('Detalle de Ángulos en las Zonas de Error');
    xlabel('Número de Dato Útil (Índice donde ha fallado)');
    ylabel('Valor (Radianes)');
    legend;
    grid on;
    
    % Añadir tooltips interactivos usando datacursormode
    % Al hacer clic en un punto, verás los 3 valores!
    dcm = datacursormode(gcf);
    datacursormode on;
    
    fprintf('\n-> Usa el ratón para hacer CLIC en los puntos rojos o azules de la figura "Visor de Errores Detallado" para inspeccionarlos.\n');
else
    fprintf('\n¡PERFECTO! No hay errores significativos (> 0.1 radianes) en la prueba aislada.\n');
end
