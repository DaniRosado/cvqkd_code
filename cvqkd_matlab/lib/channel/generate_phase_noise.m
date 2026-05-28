function [phase_total, phase_wiener, phase_acoustic] = generate_phase_noise(N_samples, Ts, cfg)
% GENERATE_PHASE_NOISE - Generates realistic fiber channel phase noise
%
% INPUTS:
%   N_samples - Number of time samples
%   Ts        - Sample period (seconds)
%   cfg       - Configuration structure with fields:
%               .linewidth_hz     - Laser linewidth (Hz)
%               .acoustic_freq_hz - Acoustic vibration frequency (Hz)
%               .acoustic_amp     - Acoustic amplitude (radians)
%
% OUTPUTS:
%   phase_total    - Total phase noise (Wiener + Acoustic)
%   phase_wiener   - Wiener process component (laser linewidth)
%   phase_acoustic - Acoustic vibration component
%
% ALGORITHM:
%   Phase noise = Wiener process + Sinusoidal acoustic term
%   - Wiener: Models laser phase diffusion (linewidth)
%   - Acoustic: Models fiber vibrations and environmental effects

t = (0:N_samples-1)' * Ts;

% Wiener process (cumulative random walk)
sigma_w = sqrt(2 * pi * cfg.linewidth_hz * Ts);
phase_wiener = cumsum(sigma_w * randn(N_samples, 1));

% Acoustic vibration (deterministic sinusoid)
phase_acoustic = cfg.acoustic_amp * sin(2 * pi * cfg.acoustic_freq_hz * t);

% Total phase drift
phase_total = phase_wiener + phase_acoustic;

end
