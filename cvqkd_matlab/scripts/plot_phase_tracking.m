% Script para comparar la fase interpolada del FPGA frente al Ideal de MATLAB
%clear; clc; close all;

disp('Cargando sim_phase_interp.txt...');
data = load('C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/sim_phase_interp.txt');

% Columnas: [fase_datos_count, fase_vivado, fase_matlab]
idx         = data(:, 1);
fase_vivado = data(:, 2) / 32768.0; % Convertir de 3Q15 a radianes
fase_matlab = data(:, 3) / 32768.0; % Convertir de 3Q15 a radianes

figure('Name', 'Tracking de Fase del CORDIC (Interpolador)', 'NumberTitle', 'off', 'Position', [150, 150, 1200, 600]);

plot(idx, fase_matlab, 'r-', 'LineWidth', 2, 'DisplayName', 'Ideal (MATLAB)'); hold on;
plot(idx, fase_vivado, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Interpolado (Vivado)');

title('Evolución de la Fase Interpolada (Vivado vs MATLAB)');
xlabel('Número de Dato Útil');
ylabel('Fase (Radianes)');
legend;
grid on;

% Ampliar un poco los ejes Y para que se vea claro el +pi y -pi
ylim([-4, 4]);

% Gráfica del error de interpolación en el tiempo
figure('Name', 'Error de Interpolación', 'NumberTitle', 'off', 'Position', [200, 200, 1200, 400]);

% Utilizamos la proyección en el plano complejo (fasores) para obtener
% de forma infalible la diferencia física real entre ambos ángulos
% y evitar cualquier artefacto por el cruce en +-pi:
error_fase_bruto = fase_vivado - fase_matlab;
error_fase_real = angle(exp(1j * error_fase_bruto));

plot(idx, error_fase_real, 'k');
title('Error Real de Interpolación (Físico)');
xlabel('Número de Dato Útil');
ylabel('Error (Radianes)');
% Ajustamos los ejes Y a una escala milimétrica para ver el ruido real

grid on;
