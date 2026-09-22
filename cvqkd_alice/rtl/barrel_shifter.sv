`timescale 1ns / 1ps

module barrel_shifter #(
    parameter int Z = 384,
    parameter int W = 8
)(
    input  logic [W-1:0] data_in  [0:Z-1], // Array de Z LLRs
    input  logic [8:0]   shift_val,        // 0 a 383
    input  logic         dir_inverse,      // 0 = Directo (VNU->CNU), 1 = Inverso (CNU->VNU)
    output logic [W-1:0] data_out [0:Z-1]
);

    // Número de etapas logarítmicas necesarias: ceil(log2(Z))
    // Para Z = 384 -> 9 etapas (2^8 = 256 < 384 <= 2^9 = 512)
    // Para Z = 8   -> 3 etapas
    localparam int NUM_STAGES = (Z > 1) ? $clog2(Z) : 1;

    // Cálculo del desplazamiento efectivo unificado (lógica combinacional pura, 0 ciclos):
    // En modo directo (dir_inverse = 0): rotación hacia adelante de shift_val posiciones.
    // En modo inverso (dir_inverse = 1): deshace la rotación rotando (Z - shift_val) % Z.
    logic [NUM_STAGES-1:0] eff_shift;

    always_comb begin
        int norm_shift;
        norm_shift = int'(shift_val) % Z;
        if (norm_shift == 0) begin
            eff_shift = '0;
        end else if (dir_inverse == 1'b0) begin
            eff_shift = norm_shift[NUM_STAGES-1:0];
        end else begin
            eff_shift = (Z - norm_shift);
        end
    end

    // Red de multiplexores en cascada (100% combinacional, 0 ciclos de latencia de reloj)
    logic [W-1:0] stage [0:NUM_STAGES][0:Z-1];

    // Conexión directa de entrada a la etapa 0
    always_comb begin
        for (int i = 0; i < Z; i++) begin
            stage[0][i] = data_in[i];
        end
    end

    // Generación física por capas (árbol de multiplexores 2:1)
    genvar s, j;
    generate
        for (s = 0; s < NUM_STAGES; s++) begin : gen_stages
            localparam int S = (1 << s) % Z;
            
            for (j = 0; j < Z; j++) begin : gen_mux
                localparam int SRC_IDX = (j >= S) ? (j - S) : (j + Z - S);
                
                assign stage[s+1][j] = eff_shift[s] ? stage[s][SRC_IDX] : stage[s][j];
            end
        end
    endgenerate

    // Conexión de la última etapa a la salida
    always_comb begin
        for (int i = 0; i < Z; i++) begin
            data_out[i] = stage[NUM_STAGES][i];
        end
    end

endmodule