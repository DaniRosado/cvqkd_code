`timescale 1ns / 1ps

import bg_rom_pkg::*; // Importamos MB=46, NB=68 y BG_ROM [cite: 1, 2]

module ldpc_rom_controller (
    input  logic         clk,
    input  logic [5:0]   current_row, // Fila actual (0 a 45) [cite: 1]
    input  logic [6:0]   current_col, // Columna actual (0 a 67) [cite: 1]
    
    // Salidas hacia el Datapath y Memorias
    output logic [8:0]   shift_val,   // Valor de rotación (Z=384 -> 9 bits)
    output logic [6:0]   p_ram_addr,  // Dirección para la P_mem (coincide con col)
    output logic [11:0]  r_ram_addr,  // Dirección para R_mem (basada en fila y col)
    output logic         valid_entry  // Indica si el valor != -1 
);

    // 1. Lectura directa de la ROM cargada en el package 
    shortint rom_data;
    assign rom_data = BG_ROM[current_row][current_col];

    // 2. Lógica de validación y extracción de desplazamiento
    always_comb begin
        if (rom_data == -1) begin 
            valid_entry = 1'b0;
            shift_val   = 9'd0;
        end else begin
            valid_entry = 1'b1;
            // El valor en la ROM es el desplazamiento [cite: 2, 38]
            shift_val   = rom_data[8:0]; 
        end
    end

    // 3. Direccionamiento de Memorias
    // Para P_mem, la dirección es simplemente la columna (NB=68) [cite: 1]
    assign p_ram_addr = current_col;

    // Para R_mem, necesitamos una dirección única para cada conexión válida.
    // Una forma sencilla es: addr = (fila * NB) + columna
    assign r_ram_addr = (12'(current_row) * 12'd68) + 12'(current_col);

endmodule