`timescale 1ns / 1ps

// Agrupa 4 muestras {Q, P} de 32 bits en un bloque 8D de 128 bits para el MDR.
// valid_data es un pulso de 1 ciclo cuando data_out contiene un bloque completo;
// data_out se mantiene hasta que entra la siguiente muestra.
module mdr_accumulator (
    input  logic         clk,
    input  logic         rst_n,

    // Entrada desde el Router
    input  logic         valid_in,
    input  logic [31:0]  data_in,     // {Q, P}

    // Salida hacia MDR y Síndrome
    output logic         valid_data,
    output logic [127:0] data_out     // 8 símbolos de 16 bits, la primera muestra en los bits bajos
);

    logic [1:0] cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt        <= '0;
            valid_data <= 1'b0;
        end else begin
            valid_data <= valid_in && (cnt == 2'd3);
            if (valid_in) cnt <= cnt + 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (valid_in) data_out <= {data_in, data_out[127:32]};
    end

endmodule
