% exportar_test_shifter.m
% Ejecutar DESPUÉS de tb_generador_master.m
disp('--- Generando vectores de prueba masivos para el Barrel Shifter ---');

Z = 384;
[mb, nb] = size(bg_matrix);

% Rutas de exportación
fid_in    = fopen(fullfile(DATA_DIR, 'shifter_in.txt'), 'w');
fid_out   = fopen(fullfile(DATA_DIR, 'shifter_out.txt'), 'w');
fid_shift = fopen(fullfile(DATA_DIR, 'shifter_shift.txt'), 'w');

num_tests = 0;

for r = 1:mb
    for c = 1:nb
        shift = bg_matrix(r, c);
        
        % Solo procesamos aristas reales (donde shift != -1)
        if shift ~= -1
            
            % 1. Extraemos el array y lo pasamos a 8-bit Signo-Magnitud
            vnu_array_sm = zeros(1, Z);
            for z = 1:Z
                % llr_ch_matrix ya viene con el llr_scale aplicado desde el master
                val = round(llr_ch_matrix(c, z)); 
                
                % Saturación
                if val > 127, val = 127; end
                if val < -127, val = -127; end
                
                % Signo-Magnitud
                if val < 0
                    vnu_array_sm(z) = 128 + abs(val);
                else
                    vnu_array_sm(z) = val;
                end
            end
            
            % 2. La Verdad Absoluta: Rotamos a la derecha usando circshift
            cnu_array_sm = circshift(vnu_array_sm, [0, shift]);
            
            % 3. Formateo a binario y Endianness (Z bajando a 1)
            str_in = '';
            str_out = '';
            for z = Z:-1:1
                str_in  = [str_in, dec2bin(vnu_array_sm(z), 8)];
                str_out = [str_out, dec2bin(cnu_array_sm(z), 8)];
            end
            
            % 4. Guardamos la terna en los archivos de texto
            fprintf(fid_in, '%s\n', str_in);
            fprintf(fid_out, '%s\n', str_out);
            fprintf(fid_shift, '%s\n', dec2bin(shift, 9));
            
            num_tests = num_tests + 1;
        end
    end
end

fclose(fid_in);
fclose(fid_out);
fclose(fid_shift);
fprintf('¡ÉXITO! %d vectores de prueba generados listos para Vivado.\n', num_tests);