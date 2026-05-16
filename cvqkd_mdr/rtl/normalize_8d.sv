`timescale 1ns / 1ps

module normalize_8d #(
    parameter int W = 16       // Input width (signed)
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         valid_in,
    input  logic signed [W-1:0] x0, x1, x2, x3, x4, x5, x6, x7,
    input  logic [17:0]  norm,
    output logic         valid_out,
    output logic signed [31:0] n0, n1, n2, n3, n4, n5, n6, n7
);

    // Get reciprocal of norm in Q1.31
    logic [31:0] recip_q31;
    reciprocal_lut_256 #(.NORM_W(18)) recip_inst (
        .norm(norm),
        .recip_q31(recip_q31)
    );

    // Multiply each component by reciprocal: result in Q1.31
    // x_i (int16) × recip_q31 (Q1.31) → Q17.31 → lower 32 bits = Q1.31
    logic signed [47:0] p0, p1, p2, p3, p4, p5, p6, p7;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {n0, n1, n2, n3, n4, n5, n6, n7} <= 0;
            valid_out <= 0;
        end else begin
            p0 = $signed(x0) * $signed(recip_q31);
            p1 = $signed(x1) * $signed(recip_q31);
            p2 = $signed(x2) * $signed(recip_q31);
            p3 = $signed(x3) * $signed(recip_q31);
            p4 = $signed(x4) * $signed(recip_q31);
            p5 = $signed(x5) * $signed(recip_q31);
            p6 = $signed(x6) * $signed(recip_q31);
            p7 = $signed(x7) * $signed(recip_q31);

            n0 <= p0[31:0];  // Q1.31 (lower 32 bits of Q17.31 product)
            n1 <= p1[31:0];
            n2 <= p2[31:0];
            n3 <= p3[31:0];
            n4 <= p4[31:0];
            n5 <= p5[31:0];
            n6 <= p6[31:0];
            n7 <= p7[31:0];
            valid_out <= valid_in;
        end
    end

endmodule