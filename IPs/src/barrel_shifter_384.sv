module barrel_shifter_384 (
    input  logic [383:0] data_in,
    input  logic [8:0]   shift_val, // Valor de 0 a 383
    output logic [383:0] data_out
);

    // Array interno para conectar las etapas
    logic [383:0] stage [0:9];

    // La entrada se conecta directamente a la etapa 0
    assign stage[0] = data_in;

    // Utilizamos generate para instanciar físicamente el hardware por capas
    genvar i;
    generate
        for (i = 0; i < 9; i++) begin : gen_shift_stages
            // Calculamos el tamaño del salto como parámetro constante local
            localparam int SHIFT_AMNT = 1 << i;
            
            always_comb begin
                if (shift_val[i] == 1'b1) begin
                    // Rotación circular a la derecha
                    stage[i+1] = {stage[i][SHIFT_AMNT-1 : 0], stage[i][383 : SHIFT_AMNT]};
                end else begin
                    // No rota en esta capa
                    stage[i+1] = stage[i];
                end
            end
        end
    endgenerate
    
    // La salida final es el resultado de la etapa 9
    assign data_out = stage[9];

endmodule