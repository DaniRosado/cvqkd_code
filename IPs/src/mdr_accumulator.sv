`timescale 1ns / 1ps

module mdr_accumulator (
    input  logic         clk,
    input  logic         rst_n,
    
    // Entrada desde el Router
    input  logic         valid_in,
    input  logic [31:0]  data_in,     // {Q, P}
    
    // Salida hacia MDR y Síndrome
    output logic         valid_data,
    output logic [127:0] data_out     // 8 símbolos de 16 bits
);

    logic [1:0]   cnt;
    logic [127:0] shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt        <= '0;
            shift_reg  <= '0;
            valid_data <= 1'b0;
            data_out   <= '0;
        end else begin
            valid_data <= 1'b0; // Por defecto a 0, solo es un pulso
            
            if (valid_in) begin
                // Desplazamos e insertamos el nuevo par de símbolos
                // El Endianness dependerá de cómo lo lea tu MDR internamente
                shift_reg <= {data_in, shift_reg[127:32]}; 
                
                if (cnt == 2'd3) begin
                    cnt        <= '0;
                    valid_data <= 1'b1;
                    data_out   <= {data_in, shift_reg[127:32]}; // Sacamos la palabra completa
                end else begin
                    cnt <= cnt + 1;
                end
            end
        end
    end
endmodule