`timescale 1ns / 1ps

module norm_8d #(
    parameter int W = 16     // Input width (signed)
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         valid_in,
    input  logic signed [W-1:0] x0, x1, x2, x3, x4, x5, x6, x7,
    output logic         valid_out,
    output logic [17:0]  norm       // sqrt(sum(xi^2)) as integer
);

    // Stage 1: squares (8 parallel, 16×16 → 32 unsigned)
    logic [31:0] sq0, sq1, sq2, sq3, sq4, sq5, sq6, sq7;
    logic        v1;

    always_ff @(posedge clk) begin
        v1 <= valid_in;
        if (valid_in) begin
            sq0 <= $unsigned(32'(x0) * 32'(x0));
            sq1 <= $unsigned(32'(x1) * 32'(x1));
            sq2 <= $unsigned(32'(x2) * 32'(x2));
            sq3 <= $unsigned(32'(x3) * 32'(x3));
            sq4 <= $unsigned(32'(x4) * 32'(x4));
            sq5 <= $unsigned(32'(x5) * 32'(x5));
            sq6 <= $unsigned(32'(x6) * 32'(x6));
            sq7 <= $unsigned(32'(x7) * 32'(x7));
        end
    end

    // Stage 2: adder tree (pairwise sums → 33-bit)
    logic [32:0] sum01, sum23, sum45, sum67;
    logic        v2;

    always_ff @(posedge clk) begin
        v2 <= v1;
        sum01 <= $unsigned(sq0) + $unsigned(sq1);
        sum23 <= $unsigned(sq2) + $unsigned(sq3);
        sum45 <= $unsigned(sq4) + $unsigned(sq5);
        sum67 <= $unsigned(sq6) + $unsigned(sq7);
    end

    // Stage 3: final sum (34-bit)
    logic [33:0] sum_all;
    logic        v3;

    always_ff @(posedge clk) begin
        v3 <= v2;
        sum_all <= $unsigned(sum01) + $unsigned(sum23) +
                   $unsigned(sum45) + $unsigned(sum67);
    end

    // Stage 4: CORDIC sqrt
    // Vivado CORDIC IP: sqrt mode, 34-bit input, 18-bit output, ~18 cycles latency
    // We instantiate a behavioral sqrt for simulation (compatible with CORDIC timing)

    localparam int CORDIC_LAT = 18;
    logic [33:0] sum_reg [0:CORDIC_LAT-1];
    logic        v_reg [0:CORDIC_LAT-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < CORDIC_LAT; i++) begin
                sum_reg[i] <= 0;
                v_reg[i] <= 0;
            end
            norm <= 0;
            valid_out <= 0;
        end else begin
            // Shift register for valid + sum (to match CORDIC latency)
            sum_reg[0] <= sum_all;
            v_reg[0] <= v3;
            for (int i = 1; i < CORDIC_LAT; i++) begin
                sum_reg[i] <= sum_reg[i-1];
                v_reg[i] <= v_reg[i-1];
            end

            // Behavioral sqrt (replace with CORDIC IP in Vivado)
            if (v_reg[CORDIC_LAT-1]) begin
                norm <= sqrt_approx(sum_reg[CORDIC_LAT-1]);
            end
            valid_out <= v_reg[CORDIC_LAT-1];
        end
    end

    function automatic logic [17:0] sqrt_approx(input logic [33:0] val);
        logic [33:0] rem, root, div;
        rem = val;
        root = 0;
        for (int i = 16; i >= 0; i--) begin
            div = (root << 1) + (1 << i);
            if (rem >= (div << i)) begin
                rem = rem - (div << i);
                root = root + (1 << i);
            end
        end
        return root[17:0];
    endfunction

endmodule