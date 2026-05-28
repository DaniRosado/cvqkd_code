function params = estimate_parameters_float(P_alice, Q_alice, P_bob, Q_bob, VarA_adc)
% ESTIMATE_PARAMETERS_FLOAT - Floating-point parameter estimation
%
% INPUTS:
%   P_alice, Q_alice - Alice's quadratures (sacrificed samples)
%   P_bob, Q_bob     - Bob's quadratures (sacrificed samples)
%   VarA_adc         - Alice's variance (ADC units²)
%
% OUTPUTS:
%   params - Structure with fields:
%            .var_B        - Bob's variance
%            .cov_AB       - Alice-Bob covariance
%            .sigma        - sqrt(var_B)
%            .sqrt_T_eta   - sqrt(T*eta) = Cov/VarA
%            .T_eta        - T*eta (transmittance × efficiency)
%
% ALGORITHM:
%   Uses MATLAB native var() and cov() functions

% Bob's variance (average over both quadratures)
params.var_B = (var(double(P_bob), 1) + var(double(Q_bob), 1)) / 2;

% Alice-Bob covariance (average over both quadratures)
cov_mat_P = cov(double(P_alice), double(P_bob), 1);
cov_mat_Q = cov(double(Q_alice), double(Q_bob), 1);
params.cov_AB = (cov_mat_P(1,2) + cov_mat_Q(1,2)) / 2;

% Derived parameters
params.sigma = sqrt(params.var_B);
params.sqrt_T_eta = params.cov_AB / VarA_adc;
params.T_eta = params.sqrt_T_eta^2;

end
