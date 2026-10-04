%% ========================================================================
%  CURVA WATERFALL DE LA RECONCILIACIÓN DE ALICE (RTL)
%  Lee los resultados de tools/waterfall_ldpc.sh (build/waterfall) y dibuja,
%  frente a la SNR, la tasa de tramas reconciliadas y las iteraciones del LDPC
%  de cada trama reconciliada.
%  Salida: build/waterfall/fig_waterfall.pdf
% ========================================================================
SCRIPT_DIR = fileparts(mfilename('fullpath'));
if isempty(SCRIPT_DIR), SCRIPT_DIR = pwd(); end
WF_DIR = fullfile(SCRIPT_DIR, '..', '..', 'build', 'waterfall');

r = sortrows(readtable(fullfile(WF_DIR, 'resumen.csv')), 'snr_dim');   % Una fila por distancia
t = readtable(fullfile(WF_DIR, 'waterfall.csv'));                        % Una fila por trama
ok = t.convergido == 1 & t.columnas_distintas == 0;

fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [0 0 16 9]);
theme(fig, 'light');   % Fondo blanco para la memoria

yyaxis left
plot(r.snr_dim, 100 * r.tasa_exito, '-o', 'LineWidth', 1.5);
ylabel('Tramas reconciliadas (%)');
ylim([-5 110]);
text(r.snr_dim, 100 * r.tasa_exito + 5, compose('%g km', r.distancia_km), ...
     'HorizontalAlignment', 'center', 'FontSize', 7);

yyaxis right
plot(t.snr_dim(ok), t.iteraciones(ok), 's', 'MarkerSize', 4);
ylabel('Iteraciones LDPC (tramas reconciliadas)');
ylim([0 200]);

xlabel('SNR por dimensión');
grid on;

exportgraphics(fig, fullfile(WF_DIR, 'fig_waterfall.pdf'), 'ContentType', 'vector');
fprintf('Figura en %s\n', fullfile(WF_DIR, 'fig_waterfall.pdf'));
