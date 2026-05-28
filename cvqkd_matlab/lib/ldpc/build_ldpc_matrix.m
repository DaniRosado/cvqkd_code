function H = build_ldpc_matrix(bg_matrix, Z)
% BUILD_LDPC_MATRIX - Constructs sparse LDPC parity-check matrix via lifting
%
% INPUTS:
%   bg_matrix - Base graph (mb × nb) with shift values or -1
%   Z         - Lifting factor (submatrix size)
%
% OUTPUTS:
%   H - Sparse parity-check matrix ((mb*Z) × (nb*Z))
%
% ALGORITHM:
%   For each base graph entry:
%   - If value == -1: Zero submatrix
%   - If value >= 0: Circulant permutation of identity by 'value' positions

[mb, nb] = size(bg_matrix);
H = sparse(mb*Z, nb*Z);

fprintf('Building LDPC matrix H (%d × %d)...\n', mb*Z, nb*Z);

for i = 1:mb
    for j = 1:nb
        shift = bg_matrix(i, j);
        if shift ~= -1
            % Create circulant permutation of identity matrix
            I_z = speye(Z);
            circulant = circshift(I_z, [0, shift]);
            H((i-1)*Z+1 : i*Z, (j-1)*Z+1 : j*Z) = circulant;
        end
    end
end

fprintf('  Sparse matrix: %d non-zero entries (%.2f%% density)\n', ...
        nnz(H), 100*nnz(H)/numel(H));

end
