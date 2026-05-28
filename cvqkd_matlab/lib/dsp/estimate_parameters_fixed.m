function params = estimate_parameters_fixed(P_alice, Q_alice, P_bob, Q_bob, VarA_adc, N_samples, cfg)
% ESTIMATE_PARAMETERS_FIXED - Fixed-point parameter estimation (FPGA emulation)
%
% INPUTS:
%   P_alice, Q_alice - Alice's int16 quadratures
%   P_bob, Q_bob     - Bob's int16 quadratures
%   VarA_adc         - Alice's variance (integer)
%   N_samples        - Number of samples
%   cfg              - Configuration with .fixed_point.* fields
%
% OUTPUTS:
%   params - Structure with fixed-point values:
%            .var_B_fp        - Bob's variance (integer)
%            .sigma_fp        - Sigma (Q16.16 format)
%            .sqrt_T_eta_fp   - Sqrt(T*eta) (Q16.16 format)
%            .T_eta_fp        - T*eta (Q16.16 format)
%
% ALGORITHM:
%   Emulates LLR_Math_Unit FPGA logic with 64-bit accumulators

% Accumulate sums (int64 to prevent overflow)
sum_P_B = sum(int64(P_bob));
sum_Q_B = sum(int64(Q_bob));
sum_P_A = sum(int64(P_alice));
sum_Q_A = sum(int64(Q_alice));

sum_sq_P_B = sum(int64(P_bob).^2);
sum_sq_Q_B = sum(int64(Q_bob).^2);
sum_cov_P = sum(int64(P_alice) .* int64(P_bob));
sum_cov_Q = sum(int64(Q_alice) .* int64(Q_bob));

% Inverse constant: 2^45 / ((N/2)^2)
N_int = int64(N_samples);
INV_2N2 = int64(round(2^cfg.fixed_point.INV_2N2_shift / ((N_samples/2)^2)));

% Covariance numerator: N*(sum_xy) - sum_x*sum_y
% Ensure all operations use int64
cross_P_AB = int64(sum_P_A) * int64(sum_P_B);
cross_Q_AB = int64(sum_Q_A) * int64(sum_Q_B);
sum_cov_total = int64(sum_cov_P) + int64(sum_cov_Q);
num_cov_AB = (N_int * sum_cov_total) - (cross_P_AB + cross_Q_AB);

% Variance numerator: N*sum_x² - (sum_x)²
% Ensure all operations use int64
sq_sum_P_B = int64(sum_P_B) * int64(sum_P_B);
sq_sum_Q_B = int64(sum_Q_B) * int64(sum_Q_B);
sum_sq_total = int64(sum_sq_P_B) + int64(sum_sq_Q_B);
num_var_B = (N_int * sum_sq_total) - (sq_sum_P_B + sq_sum_Q_B);

% DEBUG: Print intermediate values
fprintf('\n=== DEBUG estimate_parameters_fixed ===\n');
fprintf('N_samples = %d\n', N_samples);
fprintf('sum_sq_P_B = %d\n', sum_sq_P_B);
fprintf('sum_sq_Q_B = %d\n', sum_sq_Q_B);
fprintf('sum_sq_total = %d\n', sum_sq_total);
fprintf('N * sum_sq_total = %d\n', N_int * sum_sq_total);
fprintf('sq_sum_P_B = %d\n', sq_sum_P_B);
fprintf('sq_sum_Q_B = %d\n', sq_sum_Q_B);
fprintf('num_var_B = %d\n', num_var_B);
fprintf('INV_2N2 = %d\n', INV_2N2);

% Division via multiplication and shift (FPGA method)
% Use typecast method (matches working tb_generador_master.m from OneDrive)
cov_AB_pure = bitshift(typecast(uint64(num_cov_AB) .* uint64(INV_2N2), 'int64'), -48);
var_B_pure = bitshift(typecast(uint64(num_var_B) .* uint64(INV_2N2), 'int64'), -48);

fprintf('num_var_B = %d\n', num_var_B);
fprintf('var_B_pure = %d\n', var_B_pure);
fprintf('=======================================\n\n');

% Final parameters
params.var_B_fp = var_B_pure;

% Sqrt(T*eta) in Q1.15 format
T_raw_15bits = bitshift(cov_AB_pure * cfg.fixed_point.Q15, 0) / int64(VarA_adc);
params.sqrt_T_eta_fp = T_raw_15bits * 2;  % Convert to Q16.16

% T*eta in Q16.16 format
params.T_eta_fp = bitshift(int64(params.sqrt_T_eta_fp).^2, -16);

% Sigma via CORDIC emulation (Q16.16)
% Match exact formula from working tb_generador_master.m
Sigma_raw_cordic = floor(sqrt(double(var_B_pure)));
params.sigma_fp = int64(Sigma_raw_cordic) * cfg.fixed_point.Q16_16;

end
