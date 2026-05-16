% Script para graficar el error de Vivado leyendo sim_errors.txt
%clear; clc; close all;

file_errors = 'C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/sim_errors.txt';

% 1. Cargar el archivo de errores usando load()
% Vivado ahora escupe 3 columnas separadas por espacio: [Muestra] [Err P] [Err Q]
disp('Cargando log de errores de Vivado...');
try
    data = load(file_errors);
catch
    error('No se pudo leer sim_errors.txt. Asegúrate de ejecutar la simulación de Vivado primero.');
end

if isempty(data)
    disp('¡El archivo está vacío! Esto significa que no se procesó ninguna muestra.');
    return;
end

% 2. Separar las columnas
muestras = data(:, 1);
err_p    = data(:, 2);
err_q    = data(:, 3);
N        = length(muestras);

% Error medio absoluto entre P y Q
err_medio = (abs(err_q) + abs(err_p)) / 2;

% 3. Graficar resultados
disp('Generando gráficas...');
figure('Name', 'Error de Fase y Cuantización: Vivado vs MATLAB', 'Position', [100, 100, 1000, 600]);

% Gráfica superior: Error de cada componente
subplot(2,1,1);
plot(muestras, err_q, 'b', 'DisplayName', 'Error en Q'); hold on;
plot(muestras, err_p, 'r', 'DisplayName', 'Error en P');
title('Error Individual de Cuadraturas (Vivado - MATLAB)');
xlabel('Número de Muestra Útil');
ylabel('Error de Amplitud (Bits ADC)');
legend();
grid on;

% Gráfica inferior: Error Medio
subplot(2,1,2);
plot(muestras, err_medio, 'k', 'LineWidth', 1.2);
title('Magnitud Media del Error (|Err\_Q| + |Err\_P|) / 2');
xlabel('Número de Muestra Útil');
ylabel('Error Medio (Bits)');
grid on;

% Mostrar estadísticas en consola
disp('=======================================');
disp('   RESUMEN DEL ERROR (VIVADO VS MATLAB)');
disp('=======================================');
fprintf('Muestras analizadas: %d\n', N);
fprintf('Error máximo en Q:   %.0f bits\n', max(abs(err_q)));
fprintf('Error máximo en P:   %.0f bits\n', max(abs(err_p)));
fprintf('Error medio total:   %.2f bits\n', mean(err_medio));
disp('=======================================');
