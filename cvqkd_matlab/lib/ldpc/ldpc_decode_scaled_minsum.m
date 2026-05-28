function [bits_decoded, metrics, mem_history] = ldpc_decode_scaled_minsum(llr_ch, syndrome_target, H, cfg)
% LDPC_DECODE_SCALED_MINSUM - Layered scaled min-sum LDPC decoder
%
% INPUTS:
%   llr_ch          - Channel LLRs (nb*Z × 1)
%   syndrome_target - Target syndrome (mb*Z × 1) [QKD: non-zero!]
%   H               - Sparse parity-check matrix
%   cfg             - Configuration with .ldpc.* fields
%
% OUTPUTS:
%   bits_decoded - Decoded bits (nb*Z × 1)
%   metrics      - Structure with convergence metrics:
%                  .unsat   - Unsatisfied checks per iteration
%                  .ber     - Bit error rate per iteration
%                  .flips   - Bit flips per iteration
%                  .iter_converged - Iteration where convergence occurred
%   mem_history  - Structure with P_mem and R_mem per iteration
%
% ALGORITHM:
%   Scaled min-sum with alpha=0.75, syndrome-based termination

[mb_z, nb_z] = size(H);
mb = cfg.ldpc.N_rows;
nb = cfg.ldpc.N_cols;
Z = cfg.ldpc.Z;

% Build edge lists from sparse matrix
[rows_h, cols_h] = find(H);
num_edges = length(rows_h);
cn_edges = cell(mb_z, 1);
vn_edges = cell(nb_z, 1);
for e = 1:num_edges
    cn_edges{rows_h(e)}(end+1) = e;
    vn_edges{cols_h(e)}(end+1) = e;
end

% Initialize messages
msg_v2c = zeros(num_edges, 1);
msg_c2v = zeros(num_edges, 1);

% Initialize VN → CN messages with channel LLR
for v = 1:nb_z
    edges_v = vn_edges{v};
    if ~isempty(edges_v)
        msg_v2c(edges_v) = llr_ch(v) * cfg.ldpc.llr_scale;
    end
end

% Tracking
metrics.unsat = zeros(cfg.ldpc.max_iter, 1);
metrics.ber = zeros(cfg.ldpc.max_iter, 1);
metrics.flips = zeros(cfg.ldpc.max_iter, 1);
bits_prev = zeros(nb_z, 1);
metrics.iter_converged = 0;

% Memory history for debugging
mem_history.p_mem = zeros(cfg.ldpc.max_iter, nb, Z);
mem_history.r_mem = zeros(cfg.ldpc.max_iter, mb, nb, Z);

fprintf('Starting LDPC decoding (scaled min-sum, alpha=%.2f)...\n', cfg.ldpc.alpha);

for iter = 1:cfg.ldpc.max_iter
    %% CN Update (Scaled Min-Sum)
    for c = 1:mb_z
        edges_c = cn_edges{c};
        if isempty(edges_c), continue; end

        msgs = msg_v2c(edges_c);
        abs_vals = abs(msgs);
        sign_vals = sign(msgs);
        sign_vals(sign_vals == 0) = 1;

        % Find min1 and min2
        [min1, min1_idx] = min(abs_vals);
        abs_vals_tmp = abs_vals;
        abs_vals_tmp(min1_idx) = inf;
        min2 = min(abs_vals_tmp);
        if isinf(min2), min2 = min1; end

        % Syndrome-based sign product
        syndrome_sign = 1 - 2 * syndrome_target(c);
        sign_prod = prod(sign_vals) * syndrome_sign;

        % Compute extrinsic messages
        for k = 1:length(edges_c)
            if k == min1_idx
                min_use = min2;
            else
                min_use = min1;
            end
            sign_excl = sign_prod * sign_vals(k);
            msg_c2v(edges_c(k)) = cfg.ldpc.alpha * sign_excl * min_use;
        end
    end

    %% VN Update
    llr_post = zeros(nb_z, 1);
    for v = 1:nb_z
        edges_v = vn_edges{v};
        if isempty(edges_v)
            llr_post(v) = llr_ch(v) * cfg.ldpc.llr_scale;
        else
            sum_c2v = sum(msg_c2v(edges_v));
            llr_post(v) = llr_ch(v) * cfg.ldpc.llr_scale + sum_c2v;
            msg_v2c(edges_v) = llr_post(v) - msg_c2v(edges_v);
        end
    end

    %% Hard Decision and Syndrome Check
    bits_decoded = (llr_post < 0);
    syndrome_est = mod(H * double(bits_decoded), 2);
    unsat = sum(syndrome_est ~= syndrome_target);

    metrics.unsat(iter) = unsat;
    metrics.ber(iter) = NaN;  % Unknown without true bits
    metrics.flips(iter) = sum(bits_decoded ~= bits_prev);
    bits_prev = bits_decoded;

    %% Store memory snapshots
    for c_idx = 1:nb
        for z_idx = 1:Z
            mem_history.p_mem(iter, c_idx, z_idx) = llr_post((c_idx-1)*Z + z_idx);
        end
    end
    for e = 1:num_edges
        c_idx = cols_h(e);
        r_idx = rows_h(e);
        block_col = ceil(c_idx / Z);
        block_row = ceil(r_idx / Z);
        z_col = mod(c_idx - 1, Z) + 1;
        mem_history.r_mem(iter, block_row, block_col, z_col) = msg_c2v(e);
    end

    %% Convergence Check
    if unsat == 0
        metrics.iter_converged = iter;
        fprintf('  [CONVERGED] Iteration %d: All syndrome checks satisfied\n', iter);
        break;
    end

    if mod(iter, 10) == 0
        fprintf('  Iter %d: %d unsatisfied checks\n', iter, unsat);
    end
end

if metrics.iter_converged == 0
    metrics.iter_converged = cfg.ldpc.max_iter;
    fprintf('  [NO CONVERGENCE] Stopped at max iterations (%d)\n', cfg.ldpc.max_iter);
end

% Trim memory history to actual iterations
mem_history.p_mem = mem_history.p_mem(1:metrics.iter_converged, :, :);
mem_history.r_mem = mem_history.r_mem(1:metrics.iter_converged, :, :, :);

end
