`timescale 1ns / 1ps

// =============================================================================
// Acumulador de momentos de una cuadratura para la estimación de parámetros:
//   sum_sq_b = sum(b^2),  sum_b = sum(b),  sum_ab = sum(a*b),  sum_a = sum(a)
// con b = muestra de Bob y a = muestra de Alice (16 bits con signo).
//
// Tubería de 3 ciclos (entrada registrada, productos en DSP48, acumulación).
// Con N < 16384 muestras las sumas de productos caben de sobra en 48 bits (la
// anchura del acumulador del DSP48); las salidas se extienden a 64 bits.
// =============================================================================
module mac_moments (
    input  logic               clk,
    input  logic               rst,
    input  logic               clear,     // Pone a cero los acumuladores (nueva trama)
    input  logic               enable,    // Muestra válida en data_a / data_b
    input  logic signed [15:0] data_a,    // Muestra de Alice
    input  logic signed [15:0] data_b,    // Muestra de Bob
    output logic signed [63:0] sum_sq_b,
    output logic signed [63:0] sum_b,
    output logic signed [63:0] sum_ab,
    output logic signed [63:0] sum_a
);

    // Etapa 1: registro de entrada
    logic signed [15:0] a1, b1;
    logic               en1;

    // Etapa 2: productos
    logic signed [31:0] sq_b2, ab2;
    logic signed [15:0] a2, b2;
    logic               en2;

    // Etapa 3: acumuladores
    logic signed [47:0] acc_sq_b, acc_b, acc_ab, acc_a;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            en1 <= 1'b0;
            en2 <= 1'b0;
            {acc_sq_b, acc_b, acc_ab, acc_a} <= '0;
        end else begin
            en1 <= enable;
            en2 <= en1;
            if (en2) begin
                acc_sq_b <= acc_sq_b + sq_b2;
                acc_b    <= acc_b    + b2;
                acc_ab   <= acc_ab   + ab2;
                acc_a    <= acc_a    + a2;
            end
        end
        a1 <= data_a;
        b1 <= data_b;
        if (en1) begin
            sq_b2 <= b1 * b1;
            ab2   <= a1 * b1;
            a2    <= a1;
            b2    <= b1;
        end
    end

    assign sum_sq_b = acc_sq_b;
    assign sum_b    = acc_b;
    assign sum_ab   = acc_ab;
    assign sum_a    = acc_a;

endmodule
