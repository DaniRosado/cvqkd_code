function [LLR_all, bits_bob_all] = compute_mdr_8d(P_alice, Q_alice, P_bob, Q_bob, sigma, cfg)
% COMPUTE_MDR_8D - Multidimensional reconciliation (8D lattice)
%
% INPUTS:
%   P_alice, Q_alice - Alice's quadratures (double)
%   P_bob, Q_bob     - Bob's quadratures (double)
%   sigma            - Effective channel noise (double)
%   cfg              - Configuration with .mdr.* fields
%
% OUTPUTS:
%   LLR_all       - LLR values (N_dim × N_blocks)
%   bits_bob_all  - Bob's random bits (N_dim × N_blocks)
%
% ALGORITHM:
%   For each 8D block:
%   1. Bob creates orthogonal basis M_Y from his measurement
%   2. Bob generates random bits and maps to ±1 (C_i)
%   3. Bob computes public message m_i = M_Y' * C_i
%   4. Alice receives m_i, constructs M_X from her measurement
%   5. Alice computes U = M_X * m_i
%   6. LLR = (2 / sigma²) * ||X|| * ||Y|| * U

N_dim = cfg.mdr.N_dimensions;
syms_per_block = cfg.mdr.symbols_per_block;
N_blocks = floor(length(P_bob) / syms_per_block);

% Truncate to block-aligned length
num_used = N_blocks * syms_per_block;
P_alice = P_alice(1:num_used);
Q_alice = Q_alice(1:num_used);
P_bob = P_bob(1:num_used);
Q_bob = Q_bob(1:num_used);

% Reshape to blocks
X = zeros(N_dim, N_blocks);
Y = zeros(N_dim, N_blocks);
for blk = 1:N_blocks
    base = (blk-1) * syms_per_block;
    X(:, blk) = [P_alice(base+1); Q_alice(base+1); ...
                 P_alice(base+2); Q_alice(base+2); ...
                 P_alice(base+3); Q_alice(base+3); ...
                 P_alice(base+4); Q_alice(base+4)];
    Y(:, blk) = [P_bob(base+1); Q_bob(base+1); ...
                 P_bob(base+2); Q_bob(base+2); ...
                 P_bob(base+3); Q_bob(base+3); ...
                 P_bob(base+4); Q_bob(base+4)];
end

% Generate random bits and compute LLRs
bits_bob_all = randi([0 1], N_dim, N_blocks);
LLR_all = zeros(N_dim, N_blocks);

inv_sigma2 = 2.0 / (sigma * sigma + eps);

for blk = 1:N_blocks
    Y_i = Y(:, blk);
    X_i = X(:, blk);

    % Bob: Normalize and construct orthogonal basis
    norm_y = norm(Y_i);
    if norm_y < eps, norm_y = 1.0; end
    Y_norm = Y_i / norm_y;
    M_Y = generar_matriz_ortogonal(Y_norm);

    % Bob: Map bits to polar (±1) and compute public message
    b_i = bits_bob_all(:, blk);
    C_i = 1 - 2*b_i;  % 0→1, 1→-1
    m_i = M_Y' * C_i;

    % Alice: Normalize and construct basis
    norm_x = norm(X_i);
    if norm_x < eps, norm_x = 1.0; end
    X_norm = X_i / norm_x;
    M_X = generar_matriz_ortogonal(X_norm);

    % Alice: Reconstruct and compute LLR
    U = M_X * m_i;
    LLR_all(:, blk) = inv_sigma2 * norm_x * norm_y * U;
end

end
