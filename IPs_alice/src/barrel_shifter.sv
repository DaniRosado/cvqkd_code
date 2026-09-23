`timescale 1ns / 1ps

// ============================================================================
// Módulo:       barrel_shifter
// Proyecto:     CV-QKD Hardware Accelerator - Subsistema Alice
// Descripción:  Desplazador de barril logarítmico de 9 etapas para Z=384 y W=8.
//               Implementado mediante concatenación vectorial continua sin
//               bucles de asignación variable, garantizando:
//               - CERO latches transparentes en síntesis.
//               - Bajo consumo de LUTs (<15k celdas) y sin explosión de memoria.
//               - Simulación instantánea en Vivado (xsim).
// ============================================================================

module barrel_shifter #(
    parameter int Z = 384,
    parameter int W = 8
)(
    input  logic [W-1:0] data_in  [0:Z-1], // Array de Z LLRs (384 símbolos de W bits)
    input  logic [8:0]   shift_val,        // Valor de desplazamiento (0 a 383)
    input  logic         dir_inverse,      // 0 = Directo (VNU->CNU), 1 = Inverso (CNU->VNU)
    output logic [W-1:0] data_out [0:Z-1]
);

    localparam int TOTAL_BITS = Z * W;

    // 1. Empaquetado combinacional del array de entrada a un vector plano
    logic [TOTAL_BITS-1:0] flat_in;
    always_comb begin
        for (int k = 0; k < Z; k++) begin
            flat_in[(k * W) +: W] = data_in[k];
        end
    end

    // 2. Cálculo del desplazamiento efectivo según la dirección
    logic [8:0] eff_shift;
    always_comb begin
        if (shift_val == 9'd0) begin
            eff_shift = 9'd0;
        end else if (dir_inverse == 1'b0) begin
            eff_shift = shift_val;
        end else begin
            eff_shift = 9'(Z) - shift_val;
        end
    end

    // 3. Etapas logarítmicas con concatenación vectorial (idéntico a Bob)
    logic [TOTAL_BITS-1:0] stage [0:9];
    assign stage[0] = flat_in;

    genvar i;
    generate
        for (i = 0; i < 9; i++) begin : gen_shift_stages
            localparam int SHIFT_SYMBOLS = 1 << i;
            localparam int SHIFT_BITS    = SHIFT_SYMBOLS * W;

            always_comb begin
                if (eff_shift[i] == 1'b1) begin
                    stage[i+1] = {stage[i][(TOTAL_BITS - SHIFT_BITS - 1) : 0], stage[i][TOTAL_BITS-1 : (TOTAL_BITS - SHIFT_BITS)]};
                end else begin
                    stage[i+1] = stage[i];
                end
            end
        end
    endgenerate

    // 4. Desempaquetado del vector plano de salida al array de LLRs
    always_comb begin
        for (int k = 0; k < Z; k++) begin
            data_out[k] = stage[9][(k * W) +: W];
        end
    end

endmodule