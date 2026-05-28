function [P_rx, Q_rx] = apply_channel_model(P_tx, Q_tx, phase_noise, cfg)
% APPLY_CHANNEL_MODEL - Applies fiber channel model (attenuation, rotation, AWGN)
%
% INPUTS:
%   P_tx        - Transmitted P quadrature (real, ADC units)
%   Q_tx        - Transmitted Q quadrature (imaginary, ADC units)
%   phase_noise - Phase rotation per sample (radians)
%   cfg         - Configuration structure with fields:
%                 .physical.T_real        - Transmittance
%                 .physical.eta_detector  - Detector efficiency
%                 .physical.xi_real       - Excess noise (SNU)
%                 .physical.V_elec_snu    - Electronic noise (SNU)
%                 .adc.N0_var             - ADC variance for 1 SNU
%
% OUTPUTS:
%   P_rx - Received P quadrature (ADC units)
%   Q_rx - Received Q quadrature (ADC units)
%
% CHANNEL MODEL:
%   1. Attenuation: sqrt(T * eta)
%   2. Phase rotation: exp(j * phase_noise)
%   3. AWGN: Shot noise + Excess noise + Electronic noise

% Attenuation
atten = sqrt(cfg.physical.T_real * cfg.physical.eta_detector);
P_ideal = atten * P_tx;
Q_ideal = atten * Q_tx;

% Phase rotation
P_rotated = P_ideal .* cos(phase_noise) - Q_ideal .* sin(phase_noise);
Q_rotated = P_ideal .* sin(phase_noise) + Q_ideal .* cos(phase_noise);

% AWGN (Shot + Excess + Electronic)
noise_total_snu = 1.0 + cfg.physical.V_elec_snu + ...
                  (cfg.physical.T_real * cfg.physical.eta_detector * cfg.physical.xi_real);
noise_total_adc = noise_total_snu * cfg.adc.N0_var;

P_rx = P_rotated + sqrt(noise_total_adc) * randn(size(P_tx));
Q_rx = Q_rotated + sqrt(noise_total_adc) * randn(size(Q_tx));

end
