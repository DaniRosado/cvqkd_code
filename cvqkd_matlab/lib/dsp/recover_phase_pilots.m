function [phase_est, phase_pilots_unwrapped] = recover_phase_pilots(P_rx, Q_rx, idx_pilots, idx_all)
% RECOVER_PHASE_PILOTS - Bob's phase recovery using pilot symbols
%
% INPUTS:
%   P_rx        - Received P quadrature (all samples)
%   Q_rx        - Received Q quadrature (all samples)
%   idx_pilots  - Indices of pilot symbols
%   idx_all     - Indices of all symbols (for interpolation)
%
% OUTPUTS:
%   phase_est              - Estimated phase for all symbols (rad)
%   phase_pilots_unwrapped - Unwrapped phase from pilots (rad)
%
% ALGORITHM:
%   1. Extract pilot phases using atan2
%   2. Unwrap phase to remove 2π discontinuities
%   3. Linear interpolation to estimate data symbol phases
%   4. Wrap to [-π, π]

% Extract pilot phases
P_pilots = P_rx(idx_pilots);
Q_pilots = Q_rx(idx_pilots);
phase_pilots_raw = atan2(Q_pilots, P_pilots);

% Critical step: Unwrap to track continuous phase drift
phase_pilots_unwrapped = unwrap(phase_pilots_raw);

% Interpolate to all symbol positions
phase_est = interp1(idx_pilots, phase_pilots_unwrapped, idx_all, 'linear', 'extrap');

% Wrap to [-π, π] for consistency
phase_est = mod(phase_est + pi, 2*pi) - pi;

% Handle NaN (shouldn't occur with 'extrap', but safety check)
nan_mask = isnan(phase_est);
if any(nan_mask)
    last_valid = find(~nan_mask, 1, 'last');
    phase_est(nan_mask) = phase_est(last_valid);
end

end
