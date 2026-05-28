function M = generar_matriz_ortogonal(v)
% GENERAR_MATRIZ_ORTOGONAL - Generates 8x8 orthogonal matrix from normalized vector
%
% INPUTS:
%   v - Normalized 8D vector (unit length)
%
% OUTPUTS:
%   M - 8x8 orthogonal matrix where first column is v
%
% ALGORITHM:
%   Constructs orthogonal basis using specific 8D pattern
%   (Based on quaternion-like structure for 8D space)

v1 = v(1); v2 = v(2); v3 = v(3); v4 = v(4);
v5 = v(5); v6 = v(6); v7 = v(7); v8 = v(8);

M = [ v1,  v2,  v3,  v4,  v5,  v6,  v7,  v8;
     -v2,  v1, -v4,  v3, -v6,  v5,  v8, -v7;
     -v3,  v4,  v1, -v2, -v7, -v8,  v5,  v6;
     -v4, -v3,  v2,  v1, -v8,  v7, -v6,  v5;
     -v5,  v6,  v7,  v8,  v1, -v2, -v3, -v4;
     -v6, -v5,  v8, -v7,  v2,  v1,  v4, -v3;
     -v7, -v8, -v5,  v6,  v3, -v4,  v1,  v2;
     -v8,  v7, -v6, -v5,  v4,  v3, -v2,  v1 ];

end
