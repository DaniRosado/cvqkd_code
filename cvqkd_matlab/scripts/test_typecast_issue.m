%% TEST_TYPECAST_ISSUE - Prueba el manejo de números negativos en typecast

clear; clc;

fprintf('===========================================\n');
fprintf(' Test: Typecast con números negativos\n');
fprintf('===========================================\n\n');

% Simular num_var_B negativo (caso problemático)
num_var_B = int64(-1000000000000);
INV_2N2 = int64(140737488);

fprintf('Inputs:\n');
fprintf('  num_var_B = %d (int64)\n', num_var_B);
fprintf('  INV_2N2   = %d (int64)\n\n', INV_2N2);

% Método original con typecast
fprintf('[1] Método typecast directo:\n');
try
    prod = uint64(num_var_B) .* uint64(INV_2N2);
    fprintf('  uint64(num_var_B) = %s\n', num2str(uint64(num_var_B)));
    fprintf('  Producto (uint64) = %s\n', num2str(prod));
    result = bitshift(typecast(prod, 'int64'), -48);
    fprintf('  Resultado >>48 = %d\n\n', result);
catch ME
    fprintf('  ERROR: %s\n\n', ME.message);
end

% Método con double intermedio (Octave)
fprintf('[2] Método double intermedio:\n');
num_var_B_d = double(num_var_B);
inv_2n2_d = double(INV_2N2);
result_double = int64(floor((num_var_B_d * inv_2n2_d) / 2^48));
fprintf('  Resultado = %d\n\n', result_double);

% Método con manejo de signo explícito
fprintf('[3] Método con manejo de signo explícito:\n');
sign_var = sign(num_var_B);
abs_var = abs(num_var_B);
prod_abs = uint64(abs_var) .* uint64(INV_2N2);
result_abs = bitshift(typecast(prod_abs, 'int64'), -48);
result_signed = sign_var * result_abs;
fprintf('  Signo = %d\n', sign_var);
fprintf('  |num_var_B| = %d\n', abs_var);
fprintf('  Producto abs = %s\n', num2str(prod_abs));
fprintf('  Resultado abs >>48 = %d\n', result_abs);
fprintf('  Resultado con signo = %d\n\n', result_signed);

fprintf('===========================================\n');
fprintf(' COMPARACIÓN\n');
fprintf('===========================================\n');
fprintf('Método                | Resultado\n');
fprintf('----------------------+-----------\n');
fprintf('Typecast directo      | %10d\n', result);
fprintf('Double intermedio     | %10d\n', result_double);
fprintf('Manejo signo explícito| %10d\n', result_signed);
fprintf('===========================================\n\n');

if result == result_double
    fprintf('[✓] Método typecast directo funciona correctamente\n');
else
    fprintf('[✗] Método typecast directo tiene problemas con negativos\n');
    fprintf('    Se debe usar double intermedio o manejo explícito de signo\n');
end
