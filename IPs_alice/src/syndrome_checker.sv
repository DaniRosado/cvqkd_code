`timescale 1ns / 1ps

module syndrome_checker #(
    parameter int Z = 384
)(
    input  logic         clk,
    input  logic         rst_n,
    
    // --- Control desde la FSM ---
    input  logic         iter_start,   // Pulso en el ciclo 0 de cada iteración completa
    input  logic         row_done,     // Pulso cuando la FASE 3 (CNU) termina una fila
    
    // --- Datos ---
    input  logic [Z-1:0] cn_signs,     // Los 384 bits 'total_sign_out' directos de los CNUs
    input  logic [Z-1:0] target_syn,   // El síndrome que mandó Alice para esta fila
    
    // --- Salida ---
    output logic         is_converged  // Vale 1 si todas las filas procesadas hasta ahora están OK
);

    logic [Z-1:0] row_errors;
    logic         row_ok;

    // Comparamos bit a bit lo que calculó la CNU con lo que dijo Alice.
    // Si coinciden, el XOR da 0. Si hay discrepancia, da 1 (error).
    assign row_errors = cn_signs ^ target_syn;
    
    // La fila solo está OK si no hay ni un solo error en los 384 bits
    assign row_ok = (row_errors == '0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_converged <= 1'b0;
        end else if (iter_start) begin
            // Al empezar una nueva iteración de la matriz, asumimos que funcionará
            is_converged <= 1'b1; 
        end else if (row_done) begin
            // Si la fila actual tiene errores, manchamos el resultado de toda la iteración
            if (!row_ok) begin
                is_converged <= 1'b0;
            end
        end
    end

endmodule