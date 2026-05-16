`timescale 1ns / 1ps

module mat_vec_mul_8x8 (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         valid_in,
    input  logic signed [31:0] v0, v1, v2, v3, v4, v5, v6, v7,  // normalized X (Q1.31)
    input  logic signed [31:0] m0, m1, m2, m3, m4, m5, m6, m7,  // public message (Q1.31)
    output logic         valid_out,
    output logic signed [31:0] u0, u1, u2, u3, u4, u5, u6, u7   // U' = M × m (Q1.31)
);

    // M = orthogonal matrix from v (generar_matriz_ortogonal(v))
    // M × m: each output = Σ M[i][j] * m_j
    // M[i][j] = ±v_k (specific reordering from octonion structure)

    // Stage 1: multiply each M element by corresponding m_j
    // 64 parallel multiplies: v_k × m_j (Q1.31 × Q1.31 → Q2.62 → Q1.31)
    logic signed [31:0] p [0:7][0:7];
    logic signed [63:0] prod [0:7][0:7];
    logic        v1_p;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1_p <= 0;
            for (int i = 0; i < 8; i++)
                for (int j = 0; j < 8; j++)
                    prod[i][j] <= 0;
        end else begin
            v1_p <= valid_in;
            // Row 0: [ v0,  v1,  v2,  v3,  v4,  v5,  v6,  v7 ] × m
            prod[0][0] <= $signed(v0) * $signed(m0);
            prod[0][1] <= $signed(v1) * $signed(m1);
            prod[0][2] <= $signed(v2) * $signed(m2);
            prod[0][3] <= $signed(v3) * $signed(m3);
            prod[0][4] <= $signed(v4) * $signed(m4);
            prod[0][5] <= $signed(v5) * $signed(m5);
            prod[0][6] <= $signed(v6) * $signed(m6);
            prod[0][7] <= $signed(v7) * $signed(m7);
            // Row 1: [ -v1,  v0, -v3,  v2, -v5,  v4,  v7, -v6 ] × m
            prod[1][0] <= -$signed(v1) * $signed(m0);
            prod[1][1] <= $signed(v0) * $signed(m1);
            prod[1][2] <= -$signed(v3) * $signed(m2);
            prod[1][3] <= $signed(v2) * $signed(m3);
            prod[1][4] <= -$signed(v5) * $signed(m4);
            prod[1][5] <= $signed(v4) * $signed(m5);
            prod[1][6] <= $signed(v7) * $signed(m6);
            prod[1][7] <= -$signed(v6) * $signed(m7);
            // Row 2: [ -v2,  v3,  v0, -v1, -v6, -v7,  v4,  v5 ] × m
            prod[2][0] <= -$signed(v2) * $signed(m0);
            prod[2][1] <= $signed(v3) * $signed(m1);
            prod[2][2] <= $signed(v0) * $signed(m2);
            prod[2][3] <= -$signed(v1) * $signed(m3);
            prod[2][4] <= -$signed(v6) * $signed(m4);
            prod[2][5] <= -$signed(v7) * $signed(m5);
            prod[2][6] <= $signed(v4) * $signed(m6);
            prod[2][7] <= $signed(v5) * $signed(m7);
            // Row 3: [ -v3, -v2,  v1,  v0, -v7,  v6, -v5,  v4 ] × m
            prod[3][0] <= -$signed(v3) * $signed(m0);
            prod[3][1] <= -$signed(v2) * $signed(m1);
            prod[3][2] <= $signed(v1) * $signed(m2);
            prod[3][3] <= $signed(v0) * $signed(m3);
            prod[3][4] <= -$signed(v7) * $signed(m4);
            prod[3][5] <= $signed(v6) * $signed(m5);
            prod[3][6] <= -$signed(v5) * $signed(m6);
            prod[3][7] <= $signed(v4) * $signed(m7);
            // Row 4: [ -v4,  v5,  v6,  v7,  v0, -v1, -v2, -v3 ] × m
            prod[4][0] <= -$signed(v4) * $signed(m0);
            prod[4][1] <= $signed(v5) * $signed(m1);
            prod[4][2] <= $signed(v6) * $signed(m2);
            prod[4][3] <= $signed(v7) * $signed(m3);
            prod[4][4] <= $signed(v0) * $signed(m4);
            prod[4][5] <= -$signed(v1) * $signed(m5);
            prod[4][6] <= -$signed(v2) * $signed(m6);
            prod[4][7] <= -$signed(v3) * $signed(m7);
            // Row 5: [ -v5, -v4,  v7, -v6,  v1,  v0,  v3, -v2 ] × m
            prod[5][0] <= -$signed(v5) * $signed(m0);
            prod[5][1] <= -$signed(v4) * $signed(m1);
            prod[5][2] <= $signed(v7) * $signed(m2);
            prod[5][3] <= -$signed(v6) * $signed(m3);
            prod[5][4] <= $signed(v1) * $signed(m4);
            prod[5][5] <= $signed(v0) * $signed(m5);
            prod[5][6] <= $signed(v3) * $signed(m6);
            prod[5][7] <= -$signed(v2) * $signed(m7);
            // Row 6: [ -v6, -v7, -v4,  v5,  v2, -v3,  v0,  v1 ] × m
            prod[6][0] <= -$signed(v6) * $signed(m0);
            prod[6][1] <= -$signed(v7) * $signed(m1);
            prod[6][2] <= -$signed(v4) * $signed(m2);
            prod[6][3] <= $signed(v5) * $signed(m3);
            prod[6][4] <= $signed(v2) * $signed(m4);
            prod[6][5] <= -$signed(v3) * $signed(m5);
            prod[6][6] <= $signed(v0) * $signed(m6);
            prod[6][7] <= $signed(v1) * $signed(m7);
            // Row 7: [ -v7,  v6, -v5, -v4,  v3,  v2, -v1,  v0 ] × m
            prod[7][0] <= -$signed(v7) * $signed(m0);
            prod[7][1] <= $signed(v6) * $signed(m1);
            prod[7][2] <= -$signed(v5) * $signed(m2);
            prod[7][3] <= -$signed(v4) * $signed(m3);
            prod[7][4] <= $signed(v3) * $signed(m4);
            prod[7][5] <= $signed(v2) * $signed(m5);
            prod[7][6] <= -$signed(v1) * $signed(m6);
            prod[7][7] <= $signed(v0) * $signed(m7);
        end
    end

    // Stage 2: sum each row's products (shift right 3 first to prevent 64-bit overflow)
    logic signed [63:0] sum [0:7];
    logic        v2_p;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v2_p <= 0;
            for (int i = 0; i < 8; i++) sum[i] <= 0;
        end else begin
            v2_p <= v1_p;
            for (int i = 0; i < 8; i++) begin
                sum[i] <= (prod[i][0] >>> 3) + (prod[i][1] >>> 3) +
                          (prod[i][2] >>> 3) + (prod[i][3] >>> 3) +
                          (prod[i][4] >>> 3) + (prod[i][5] >>> 3) +
                          (prod[i][6] >>> 3) + (prod[i][7] >>> 3);
            end
        end
    end

    // Stage 3: round and saturate to Q1.31
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {u0, u1, u2, u3, u4, u5, u6, u7} <= 0;
            valid_out <= 0;
        end else begin
            valid_out <= v2_p;
            {u0, u1, u2, u3, u4, u5, u6, u7} <= '0;
            if (v2_p) begin
                u0 <= saturate_q31(sum[0]);
                u1 <= saturate_q31(sum[1]);
                u2 <= saturate_q31(sum[2]);
                u3 <= saturate_q31(sum[3]);
                u4 <= saturate_q31(sum[4]);
                u5 <= saturate_q31(sum[5]);
                u6 <= saturate_q31(sum[6]);
                u7 <= saturate_q31(sum[7]);
            end
        end
    end

    // Shift Q2.59 sum right by 28 → Q1.31, then saturate
    // (pre-shifted by 3 in Stage 2, so total shift = 28 + 3 = 31)
    function automatic logic signed [31:0] saturate_q31(input logic signed [63:0] val);
        logic signed [63:0] shifted;
        shifted = val >>> 28;
        if (shifted > $signed(64'h000000007FFFFFFF)) return 32'h7FFFFFFF;
        else if (shifted < $signed(64'hFFFFFFFF80000000)) return 32'h80000000;
        else return shifted[31:0];
    endfunction

endmodule