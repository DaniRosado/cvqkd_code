`timescale 1ns / 1ps

module bpsk_mapper (
    input  logic [7:0] bits_in,   // 8 random bits (0 or 1)
    output logic signed [31:0] u0, u1, u2, u3, u4, u5, u6, u7  // ±1 in Q1.31
);

    // BPSK: bit=0 → +1.0 (0x7FFFFFFF), bit=1 → -1.0 (0x80000000)
    always_comb begin
        u0 = bits_in[0] ? 32'h80000000 : 32'h7FFFFFFF;
        u1 = bits_in[1] ? 32'h80000000 : 32'h7FFFFFFF;
        u2 = bits_in[2] ? 32'h80000000 : 32'h7FFFFFFF;
        u3 = bits_in[3] ? 32'h80000000 : 32'h7FFFFFFF;
        u4 = bits_in[4] ? 32'h80000000 : 32'h7FFFFFFF;
        u5 = bits_in[5] ? 32'h80000000 : 32'h7FFFFFFF;
        u6 = bits_in[6] ? 32'h80000000 : 32'h7FFFFFFF;
        u7 = bits_in[7] ? 32'h80000000 : 32'h7FFFFFFF;
    end

endmodule