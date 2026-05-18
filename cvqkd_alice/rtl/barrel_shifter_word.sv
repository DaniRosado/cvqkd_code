`timescale 1ns / 1ps

module barrel_shifter_word #(
    parameter int Z = 384, // Factor de expansión (lifting size)
    parameter int W = 8    // Ancho del dato (ej. 8 bits para LLR)
)(
    input  logic [Z*W-1:0] data_in,   // Bus gigante de entrada (3072 bits)
    input  logic [8:0]     shift_val, // Valor de rotación (0 a 383)
    output logic [Z*W-1:0] data_out   // Bus gigante de salida (3072 bits)
);

    always_comb begin
        for (int i = 0; i < Z; i++) begin
            // LDPC shift convention: VNU i receives data from position (i + shift) mod Z.
            // This is an UPWARD (right) rotation by shift_val.
            automatic int src_idx = (i + int'(shift_val)) % Z;
            data_out[i*W +: W] = data_in[src_idx*W +: W];
        end
    end

endmodule
