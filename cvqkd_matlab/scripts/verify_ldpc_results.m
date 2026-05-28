%% VERIFY_LDPC_RESULTS - Analiza resultados de decodificación LDPC
% Lee archivos generados y calcula métricas de rendimiento

clear; clc;

fprintf('========================================\n');
fprintf(' Verificación de Resultados LDPC\n');
fprintf('========================================\n\n');

DATA_DIR = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'data');

%% 1. Leer síndrome objetivo
fprintf('[1/4] Analizando síndrome objetivo...\n');
syndrome_file = fullfile(DATA_DIR, 'expected_syndrome.txt');
if ~exist(syndrome_file, 'file')
    error('No se encuentra expected_syndrome.txt. Ejecuta primero tb_generador_master.m');
end

fid = fopen(syndrome_file, 'r');
syndrome_str = '';
while ~feof(fid)
    line = fgetl(fid);
    if ischar(line)
        syndrome_str = [syndrome_str line];
    end
end
fclose(fid);

syndrome = zeros(length(syndrome_str), 1);
for i = 1:length(syndrome_str)
    syndrome(i) = str2double(syndrome_str(i));
end

total_checks = length(syndrome);
errors_initial = sum(syndrome);
check_satisfaction_initial = (1 - errors_initial/total_checks) * 100;

fprintf('  Total checks: %d\n', total_checks);
fprintf('  Checks violados inicialmente: %d (%.2f%%)\n', ...
    errors_initial, 100*errors_initial/total_checks);
fprintf('  Satisfacción inicial: %.2f%%\n\n', check_satisfaction_initial);

%% 2. Leer memorias P y R para contar iteraciones
fprintf('[2/4] Analizando memorias de decodificación...\n');
r_mem_file = fullfile(DATA_DIR, 'expected_r_mem.txt');
if ~exist(r_mem_file, 'file')
    error('No se encuentra expected_r_mem.txt');
end

% Contar líneas en R_mem
fid = fopen(r_mem_file, 'r');
r_mem_lines = 0;
while ~feof(fid)
    line = fgetl(fid);
    if ischar(line)
        r_mem_lines = r_mem_lines + 1;
    end
end
fclose(fid);

% Calcular iteraciones (asumiendo 46 filas por iteración)
N_rows = 46;
iterations_executed = floor(r_mem_lines / N_rows);

fprintf('  Líneas en R_mem: %d\n', r_mem_lines);
fprintf('  Iteraciones ejecutadas: ~%d\n\n', iterations_executed);

%% 3. Comparar claves Alice vs Bob
fprintf('[3/4] Comparando claves finales...\n');
alice_key_file = fullfile(DATA_DIR, 'bob_key_ref.txt');  % Clave de referencia
bob_decoded_file = fullfile(DATA_DIR, 'u_bits.txt');     % Bits decodificados

if ~exist(alice_key_file, 'file') || ~exist(bob_decoded_file, 'file')
    warning('Archivos de clave no encontrados. BER no calculable.');
    ber_final = NaN;
else
    % Leer clave de Alice (referencia)
    fid = fopen(alice_key_file, 'r');
    alice_key_str = '';
    while ~feof(fid)
        line = fgetl(fid);
        if ischar(line)
            alice_key_str = [alice_key_str line];
        end
    end
    fclose(fid);

    % Leer bits decodificados de Bob (u_bits.txt tiene múltiples iteraciones por línea)
    % Cada línea tiene Z*8 bits (384*8=3072), tomamos solo los últimos Z bits
    fid = fopen(bob_decoded_file, 'r');
    bob_decoded_str = '';
    Z = 384;  % Lifting factor
    while ~feof(fid)
        line = fgetl(fid);
        if ischar(line) && length(line) > Z
            % Tomar los últimos Z bits (última iteración)
            bob_decoded_str = [bob_decoded_str line(end-Z+1:end)];
        elseif ischar(line)
            bob_decoded_str = [bob_decoded_str line];
        end
    end
    fclose(fid);

    % Convertir a vectores
    len = min(length(alice_key_str), length(bob_decoded_str));
    alice_bits = zeros(len, 1);
    bob_bits = zeros(len, 1);
    for i = 1:len
        alice_bits(i) = str2double(alice_key_str(i));
        bob_bits(i) = str2double(bob_decoded_str(i));
    end

    % Calcular BER
    bit_errors = sum(alice_bits ~= bob_bits);
    ber_final = bit_errors / len;

    fprintf('  Bits totales comparados: %d\n', len);
    fprintf('  Errores de bit: %d\n', bit_errors);
    fprintf('  BER final: %.6f (%.4f%%)\n\n', ber_final, ber_final*100);
end

%% 4. Resumen final
fprintf('========================================\n');
fprintf(' RESUMEN DE VERIFICACIÓN\n');
fprintf('========================================\n');
fprintf('Estado del síndrome:\n');
fprintf('  - Checks violados: %d de %d\n', errors_initial, total_checks);
fprintf('  - Satisfacción: %.2f%%\n', check_satisfaction_initial);
fprintf('\n');
fprintf('Decodificación LDPC:\n');
fprintf('  - Iteraciones: ~%d\n', iterations_executed);
if ~isnan(ber_final)
    fprintf('  - BER final: %.6f\n', ber_final);
    if ber_final < 1e-4
        fprintf('  - Estado: ✓ EXCELENTE (BER < 10^-4)\n');
    elseif ber_final < 1e-3
        fprintf('  - Estado: ✓ BUENO (BER < 10^-3)\n');
    elseif ber_final < 1e-2
        fprintf('  - Estado: ~ ACEPTABLE (BER < 10^-2)\n');
    else
        fprintf('  - Estado: ✗ NECESITA MEJORA (BER > 10^-2)\n');
    end
else
    fprintf('  - BER: No calculable\n');
end
fprintf('========================================\n');
