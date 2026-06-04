% =====================================================================
% ESTUDIO DE PRECISIÓN: LUT + 1 ITERACIÓN NEWTON-RAPHSON (Raíz Inversa)
% =====================================================================
clear; clc; close all;

disp('--- Evaluando Tamaños de Memoria (Semilla) para Newton-Raphson ---');

% 1. Definimos nuestro rango normalizado: x siempre estará entre [1, 2)
N_puntos = 100000;
x_test = linspace(1, 2 - 1/N_puntos, N_puntos);
y_exact = 1 ./ sqrt(x_test);

% 2. Tamaños de bus de dirección para la ROM (K bits)
% (Ej: 4 bits = 16 posiciones, 8 bits = 256 posiciones)
LUT_bits_array = [4, 6, 8, 10, 12];

for i = 1:length(LUT_bits_array)
    K = LUT_bits_array(i);
    N_entradas = 2^K;
    
    % --- FASE 1: CREACIÓN DE LA ROM ---
    % Mapeamos los índices de la ROM al rango [1, 2)
    x_lut = 1 + (0:(N_entradas-1)) / N_entradas;
    
    % Truco DSP: Para minimizar el error de cuantización de la LUT, 
    % almacenamos el valor evaluado en el centro del intervalo, no en el borde.
    x_mid = x_lut + (1 / (2 * N_entradas));
    y_rom = 1 ./ sqrt(x_mid);
    
    % --- FASE 2: EMULACIÓN DEL HARDWARE ---
    % a) El hardware extrae los K bits siguientes al primer '1'
    addr = floor((x_test - 1) * N_entradas) + 1;
    
    % b) Leemos la semilla de la ROM
    y0 = y_rom(addr);
    
    % c) El Pipeline DSP ejecuta 1 iteración de Newton-Raphson:
    % Ecuación: y1 = y0 * (1.5 - 0.5 * x * y0^2)
    y1 = y0 .* (1.5 - 0.5 .* x_test .* (y0 .^ 2));
    
    % --- FASE 3: ANÁLISIS DE ERROR ---
    error_relativo_max = max(abs(y1 - y_exact) ./ y_exact);
    
    % Convertimos el error a "Bits de precisión efectivos"
    % (Cuántos bits correctos tendríamos en un bus de salida)
    bits_precision = -log2(error_relativo_max);
    
    fprintf('LUT de %2d bits (%4d registros) -> Precisión 1 Iter: %5.2f bits | Error Max: %e\n', ...
        K, N_entradas, bits_precision, error_relativo_max);
end

disp('----------------------------------------------------------------------');
disp('Nota: Los datos originales del ADC tienen 16 bits de resolución.');
disp('Objetivo: Buscar una configuración que supere los 16-17 bits de precisión.');

% =====================================================================
% GENERADOR DE ROM SYSTEMVERILOG (LUT de 512 posiciones, Paridad LZC)
% =====================================================================
disp('   -> Generando mdr_rom_pkg.sv (LUT 512, Q24 con Paridad)...');

K = 8;
N_base = 2^K;

% 1. Mapeamos el rango [1, 2)
x_lut = 1 + (0:(N_base-1)) / N_base;
x_mid = x_lut + (1 / (2 * N_base));

% 2. Calculamos los dos bancos de memoria
y_par   = 1 ./ sqrt(x_mid);                     % Exponente Par (lzc[0] == 0)
y_impar = (1 ./ sqrt(x_mid)) * (1 / sqrt(2));   % Exponente Impar (lzc[0] == 1)

% Juntamos ambos bancos (512 valores en total)
y_rom_total = [y_par, y_impar];

% 3. Convertimos a Punto Fijo Q24
y_rom_q24 = round(y_rom_total * (2^24));

% 4. Escribimos el archivo
fid_rom = fopen('mdr_rom_pkg.sv', 'w');
fprintf(fid_rom, 'package mdr_rom_pkg;\n\n');
fprintf(fid_rom, '    // ROM de Semillas Newton-Raphson (512 posiciones)\n');
fprintf(fid_rom, '    // Direcciones 0-255:   1/sqrt(x)\n');
fprintf(fid_rom, '    // Direcciones 256-511: 1/sqrt(x) * 1/sqrt(2) [Compensacion impar]\n');
fprintf(fid_rom, '    localparam logic [23:0] INV_SQRT_ROM [0:511] = ''{\n');

for i = 1:512
    hex_val = dec2hex(y_rom_q24(i), 6);
    if i < 512
        fprintf(fid_rom, '        24''h%s,\n', hex_val);
    else
        fprintf(fid_rom, '        24''h%s\n', hex_val);
    end
end

fprintf(fid_rom, '    };\n\n');
fprintf(fid_rom, 'endpackage\n');
fclose(fid_rom);

disp('   -> ¡Archivo mdr_rom_pkg.sv generado con éxito!');