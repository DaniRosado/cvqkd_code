function [P_comp, Q_comp] = compensate_phase(P_rx, Q_rx, phase_est)
% COMPENSATE_PHASE - Rotates constellation to compensate phase drift
%
% INPUTS:
%   P_rx      - Received P quadrature
%   Q_rx      - Received Q quadrature
%   phase_est - Estimated phase (radians)
%
% OUTPUTS:
%   P_comp - Phase-compensated P quadrature
%   Q_comp - Phase-compensated Q quadrature
%
% ALGORITHM:
%   Apply inverse rotation: exp(-j * phase_est)

P_comp = P_rx .* cos(-phase_est) - Q_rx .* sin(-phase_est);
Q_comp = P_rx .* sin(-phase_est) + Q_rx .* cos(-phase_est);

end
