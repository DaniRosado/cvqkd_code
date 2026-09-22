`timescale 1ns / 1ps

module barrel_shifter #(
    parameter int Z = 384,
    parameter int W = 8
)(
    input  logic [W-1:0] data_in  [0:Z-1], // Array de 384 LLRs
    input  logic [8:0]   shift_val,        // 0 a 383
    input  logic         dir_inverse,      // 0 = Directo (VNU->CNU), 1 = Inverso (CNU->VNU)
    output logic [W-1:0] data_out [0:Z-1]
);

    always_comb begin
        for (int i = 0; i < Z; i++) begin
            if (dir_inverse == 1'b0) begin
                // Shifter Directo: Rotación hacia la "derecha" (o suma circular)
                data_out[(i + shift_val) % Z] = data_in[i];
            end else begin
                // Shifter Inverso: Rotación hacia la "izquierda" (o resta circular)
                // Usamos (Z - shift_val) para evitar números negativos en el módulo
                data_out[(i + (Z - shift_val)) % Z] = data_in[i];
            end
        end
    end

endmodule