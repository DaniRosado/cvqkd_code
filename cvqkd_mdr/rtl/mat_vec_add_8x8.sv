`timescale 1ns / 1ps

module mat_vec_add_8x8 (
    input  logic signed [31:0] v0, v1, v2, v3, v4, v5, v6, v7,
    input  logic signed [31:0] u0, u1, u2, u3, u4, u5, u6, u7,
    output logic signed [31:0] m0, m1, m2, m3, m4, m5, m6, m7
);

    // M' × U where M is an octonion orthogonal matrix from v (normalized vector)
    // Since U entries are ±1, each m_i = Σ(± v_j) for specific j reorderings
    // The signs come from M' (transpose of M from generar_matriz_ortogonal)
    //
    // M' = M^T (transpose of the octonion matrix):
    // Row 0 of M' = Column 0 of M = [ v1, -v2, -v3, -v4, -v5, -v6, -v7, -v8 ]
    // Row 1 of M' = Column 1 of M = [ v2,  v1,  v4, -v3,  v6, -v5, -v8,  v7 ]
    // Row 2 of M' = Column 2 of M = [ v3, -v4,  v1,  v2,  v7,  v8, -v5, -v6 ]
    // ... etc (transpose of generar_matriz_ortogonal)

    wire signed [31:0] s [0:7][0:7];
    assign s[0][0] = v0;  assign s[0][1] = -v1; assign s[0][2] = -v2; assign s[0][3] = -v3;
    assign s[0][4] = -v4; assign s[0][5] = -v5; assign s[0][6] = -v6; assign s[0][7] = -v7;
    assign s[1][0] = v1;  assign s[1][1] = v0;  assign s[1][2] = v3;  assign s[1][3] = -v2;
    assign s[1][4] = v5;  assign s[1][5] = -v4; assign s[1][6] = -v7; assign s[1][7] = v6;
    assign s[2][0] = v2;  assign s[2][1] = -v3; assign s[2][2] = v0;  assign s[2][3] = v1;
    assign s[2][4] = v6;  assign s[2][5] = v7;  assign s[2][6] = -v4; assign s[2][7] = -v5;
    assign s[3][0] = v3;  assign s[3][1] = v2;  assign s[3][2] = -v1; assign s[3][3] = v0;
    assign s[3][4] = v7;  assign s[3][5] = -v6; assign s[3][6] = v5;  assign s[3][7] = -v4;
    assign s[4][0] = v4;  assign s[4][1] = -v5; assign s[4][2] = -v6; assign s[4][3] = -v7;
    assign s[4][4] = v0;  assign s[4][5] = v1;  assign s[4][6] = v2;  assign s[4][7] = v3;
    assign s[5][0] = v5;  assign s[5][1] = v4;  assign s[5][2] = -v7; assign s[5][3] = v6;
    assign s[5][4] = -v1; assign s[5][5] = v0;  assign s[5][6] = -v3; assign s[5][7] = v2;
    assign s[6][0] = v6;  assign s[6][1] = v7;  assign s[6][2] = v4;  assign s[6][3] = -v5;
    assign s[6][4] = -v2; assign s[6][5] = v3;  assign s[6][6] = v0;  assign s[6][7] = -v1;
    assign s[7][0] = v7;  assign s[7][1] = -v6; assign s[7][2] = v5;  assign s[7][3] = v4;
    assign s[7][4] = -v3; assign s[7][5] = -v2; assign s[7][6] = v1;  assign s[7][7] = v0;

    // Each m_i is sum of selected components weighted by U
    // Since U[j] = ±1, we sign-adjust each term: s[i][j] × u_j = ±s[i][j] depending on u_j sign
    // u_j = +1 (0x7FFFFFFF) → keep sign; u_j = -1 (0x80000000) → negate
    // In Q1.31: negating is just bit-flipping, or: out = (u_j[31]) ? -s[i][j] : s[i][j]
    // Since u_j is ±1.0 in Q1.31, the product s[i][j] × u_j = (s[i][j] >>> 31) ^ u_j[31] ? -s[i][j] : s[i][j]
    // Actually: in Q1.31, multiplying by ±1.0 is just: if u_j is negative, negate s[i][j]

    // Select or negate based on U sign bit
    function automatic logic signed [31:0] sel(input signed [31:0] val, input logic sign);
        return sign ? -val : val;
    endfunction

    always_comb begin
        m0 = sum_and_sat(sel(s[0][0], u0[31]), sel(s[0][1], u1[31]),
                         sel(s[0][2], u2[31]), sel(s[0][3], u3[31]),
                         sel(s[0][4], u4[31]), sel(s[0][5], u5[31]),
                         sel(s[0][6], u6[31]), sel(s[0][7], u7[31]));
        m1 = sum_and_sat(sel(s[1][0], u0[31]), sel(s[1][1], u1[31]),
                         sel(s[1][2], u2[31]), sel(s[1][3], u3[31]),
                         sel(s[1][4], u4[31]), sel(s[1][5], u5[31]),
                         sel(s[1][6], u6[31]), sel(s[1][7], u7[31]));
        m2 = sum_and_sat(sel(s[2][0], u0[31]), sel(s[2][1], u1[31]),
                         sel(s[2][2], u2[31]), sel(s[2][3], u3[31]),
                         sel(s[2][4], u4[31]), sel(s[2][5], u5[31]),
                         sel(s[2][6], u6[31]), sel(s[2][7], u7[31]));
        m3 = sum_and_sat(sel(s[3][0], u0[31]), sel(s[3][1], u1[31]),
                         sel(s[3][2], u2[31]), sel(s[3][3], u3[31]),
                         sel(s[3][4], u4[31]), sel(s[3][5], u5[31]),
                         sel(s[3][6], u6[31]), sel(s[3][7], u7[31]));
        m4 = sum_and_sat(sel(s[4][0], u0[31]), sel(s[4][1], u1[31]),
                         sel(s[4][2], u2[31]), sel(s[4][3], u3[31]),
                         sel(s[4][4], u4[31]), sel(s[4][5], u5[31]),
                         sel(s[4][6], u6[31]), sel(s[4][7], u7[31]));
        m5 = sum_and_sat(sel(s[5][0], u0[31]), sel(s[5][1], u1[31]),
                         sel(s[5][2], u2[31]), sel(s[5][3], u3[31]),
                         sel(s[5][4], u4[31]), sel(s[5][5], u5[31]),
                         sel(s[5][6], u6[31]), sel(s[5][7], u7[31]));
        m6 = sum_and_sat(sel(s[6][0], u0[31]), sel(s[6][1], u1[31]),
                         sel(s[6][2], u2[31]), sel(s[6][3], u3[31]),
                         sel(s[6][4], u4[31]), sel(s[6][5], u5[31]),
                         sel(s[6][6], u6[31]), sel(s[6][7], u7[31]));
        m7 = sum_and_sat(sel(s[7][0], u0[31]), sel(s[7][1], u1[31]),
                         sel(s[7][2], u2[31]), sel(s[7][3], u3[31]),
                         sel(s[7][4], u4[31]), sel(s[7][5], u5[31]),
                         sel(s[7][6], u6[31]), sel(s[7][7], u7[31]));
    end

    // Sum with extended precision, saturate to Q1.31
    function automatic logic signed [31:0] sum_and_sat(
        input signed [31:0] t0, t1, t2, t3, t4, t5, t6, t7
    );
        logic signed [34:0] ext;
        ext = $signed(t0) + $signed(t1) + $signed(t2) + $signed(t3) +
              $signed(t4) + $signed(t5) + $signed(t6) + $signed(t7);
        if ((|ext[34:31] == 1'b0) || (&ext[34:31] == 1'b1))
            return ext[31:0];
        else if (ext[34])
            return 32'h80000000;
        else
            return 32'h7FFFFFFF;
    endfunction

endmodule