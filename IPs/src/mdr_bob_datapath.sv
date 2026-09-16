// ============================================================================
// Módulo:       mdr_bob_datapath
// Proyecto:     CV-QKD Hardware Accelerator
// Descripción:  Datapath pipelinizado: norma, raíz inversa LUT y matriz ortogonal
// Dependencias: mdr_bob_pkg.sv, mdr_rom_pkg.sv
// ----------------------------------------------------------------------------
// Notas de Arquitectura:
// Diseño altamente pipelinizado (Latencia total: 9 ciclos).
// ============================================================================

`timescale 1ns / 1ps

module mdr_bob_datapath (
    input  logic               clk,
    input  logic               rst_n,

    // --- Puertos de Entrada ---
    input  logic               valid_in,
    input  logic signed [15:0] Y_in [0:7],
    input  logic [7:0]         trng_bits,

    // --- Puertos de Salida ---
    output logic               valid_out,
    output logic signed [31:0] m_out [0:7]
);

    localparam int DIMENSIONS   = 8;
    localparam int ADC_WIDTH    = 16;
    localparam int DELAY_STAGES = 7;

    // =====================================================================
    // ETAPA 1: SUMA DE CUADRADOS (Norma al cuadrado)
    // =====================================================================
    logic unsigned [31:0] Y_sq [0:DIMENSIONS-1];

    // Nivel 1 del árbol de sumas (33 bits)
    logic unsigned [32:0] sum_lvl1_0, sum_lvl1_1, sum_lvl1_2, sum_lvl1_3;

    // Nivel 2 del árbol de sumas (34 bits)
    logic unsigned [33:0] sum_lvl2_0, sum_lvl2_1;

    // Resultado final de la Etapa 1 (35 bits)
    logic unsigned [34:0] norm_sq;
    logic                 valid_stg1;

    // Ciclo 1a: Multiplicadores (registrados)
    logic valid_sq;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_sq <= 1'b0;
            for (int i = 0; i < DIMENSIONS; i++) Y_sq[i] <= '0;
        end else begin
            valid_sq <= valid_in;
            if (valid_in) begin
                for (int i = 0; i < DIMENSIONS; i++) begin
                    Y_sq[i] <= $unsigned( 32'(Y_in[i]) * 32'(Y_in[i]) );
                end
            end
        end
    end

    // Ciclo 1b: Árbol de sumas (combinacional sobre Y_sq registrado)
    always_comb begin
        sum_lvl1_0 = Y_sq[0] + Y_sq[1];
        sum_lvl1_1 = Y_sq[2] + Y_sq[3];
        sum_lvl1_2 = Y_sq[4] + Y_sq[5];
        sum_lvl1_3 = Y_sq[6] + Y_sq[7];
        sum_lvl2_0 = sum_lvl1_0 + sum_lvl1_1;
        sum_lvl2_1 = sum_lvl1_2 + sum_lvl1_3;
    end

    // Ciclo 1c: Registro del resultado
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_stg1 <= 1'b0;
            norm_sq    <= '0;
        end else begin
            valid_stg1 <= valid_sq;
            if (valid_sq) begin
                norm_sq <= sum_lvl2_0 + sum_lvl2_1;
            end
        end
    end

    // =====================================================================
    // ETAPA 2: LZC + SEMILLA ROM + NEWTON-RAPHSON (Raíz Inversa)
    // =====================================================================

    // ---------------------------------------------------------------------
    // Ciclo 1: Leading Zero Counter (LZC) y Normalización
    // ---------------------------------------------------------------------
    logic [5:0]  lzc;
    logic [34:0] norm_sq_shifted;
    logic [8:0]  rom_addr;
    logic [5:0]  final_shift_reg1;
    logic        valid_stg2_c1;

    always_comb begin
        lzc = 6'd35;
        for (int i = 34; i >= 0; i--) begin
            if (norm_sq[i]) begin
                lzc = 34 - i;
                break;
            end
        end
    end

    logic [34:0] norm_sq_shifted_comb;
    assign norm_sq_shifted_comb = norm_sq << lzc;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_stg2_c1 <= 1'b0;
        end else begin
            valid_stg2_c1 <= valid_stg1;
            if (valid_stg1) begin
                norm_sq_shifted  <= norm_sq_shifted_comb;
                rom_addr         <= {lzc[0], norm_sq_shifted_comb[33:26]};
                final_shift_reg1 <= (6'd34 - lzc) >> 1;
            end
        end
    end

    // ---------------------------------------------------------------------
    // Ciclo 2: Lectura de la ROM de Semillas
    // ---------------------------------------------------------------------
    logic [23:0] y0;
    logic [34:0] x_norm_reg;
    logic [5:0]  final_shift_reg2;
    logic        valid_stg2_c2;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_stg2_c2 <= 1'b0;
        end else begin
            valid_stg2_c2 <= valid_stg2_c1;
            if (valid_stg2_c1) begin
                y0               <= mdr_rom_pkg::INV_SQRT_ROM[rom_addr];
                x_norm_reg       <= norm_sq_shifted;
                final_shift_reg2 <= final_shift_reg1;
            end
        end
    end

    // ---------------------------------------------------------------------
    // Ciclo 3: Pasamos la semilla directamente (sin Newton-Raphson por ahora)
    // ---------------------------------------------------------------------
    logic [23:0] inv_sqrt_val;
    logic [5:0]  final_shift_reg3;
    logic        valid_stg2_c3;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_stg2_c3 <= 1'b0;
        end else begin
            valid_stg2_c3 <= valid_stg2_c2;
            if (valid_stg2_c2) begin
                inv_sqrt_val     <= y0;
                final_shift_reg3 <= final_shift_reg2;
            end
        end
    end

    // =====================================================================
    // LA SALA DE ESPERA: Shift Registers (Alineación de Pipeline)
    // =====================================================================
    logic signed [ADC_WIDTH-1:0] Y_in_delay [0:DELAY_STAGES-1][0:DIMENSIONS-1];
    logic [DIMENSIONS-1:0]       trng_bits_delay [0:DELAY_STAGES-1];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < DELAY_STAGES; i++) begin
                for (int j = 0; j < DIMENSIONS; j++) Y_in_delay[i][j] <= '0;
                trng_bits_delay[i] <= '0;
            end
        end else begin
            for (int j = 0; j < DIMENSIONS; j++) Y_in_delay[0][j] <= Y_in[j];
            trng_bits_delay[0] <= trng_bits;

            for (int i = 1; i < DELAY_STAGES; i++) begin
                for (int j = 0; j < DIMENSIONS; j++) Y_in_delay[i][j] <= Y_in_delay[i-1][j];
                trng_bits_delay[i] <= trng_bits_delay[i-1];
            end
        end
    end

    // =====================================================================
    // ETAPA 3: NORMALIZACIÓN (Multiplicación Escalar)
    // =====================================================================
    logic signed [40:0] Y_mult [0:DIMENSIONS-1];
    logic signed [31:0] Y_norm [0:DIMENSIONS-1];
    logic               valid_stg3_mult;
    logic               valid_stg3;
    logic [5:0]         final_shift_reg4;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_stg3_mult  <= 1'b0;
            valid_stg3       <= 1'b0;
            final_shift_reg4 <= '0;
            for (int i = 0; i < DIMENSIONS; i++) begin
                Y_mult[i] <= '0;
                Y_norm[i] <= '0;
            end
        end else begin
            // Ciclo A: Multiplicación
            valid_stg3_mult <= valid_stg2_c3;
            if (valid_stg2_c3) begin
                final_shift_reg4 <= final_shift_reg3;
                for (int i = 0; i < DIMENSIONS; i++) begin
                    Y_mult[i] <= Y_in_delay[4][i] * $signed({1'b0, inv_sqrt_val});
                end
            end

            // Ciclo B: Shift y truncamiento (un ciclo después de la multiplicación)
            valid_stg3 <= valid_stg3_mult;
            if (valid_stg3_mult) begin
                for (int i = 0; i < DIMENSIONS; i++) begin
                    Y_norm[i] <= 32'(Y_mult[i] >>> final_shift_reg4);
                end
            end
        end
    end

    // =====================================================================
    // ETAPA 4: MATRIZ ORTOGONAL (Generación del Mensaje Público)
    // =====================================================================

    // 1. ADN de la Matriz (Índices de la matriz transpuesta)
    localparam int M_IDX [0:DIMENSIONS-1][0:DIMENSIONS-1] = '{
        '{0, 1, 2, 3, 4, 5, 6, 7},
        '{1, 0, 3, 2, 5, 4, 7, 6},
        '{2, 3, 0, 1, 6, 7, 4, 5},
        '{3, 2, 1, 0, 7, 6, 5, 4},
        '{4, 5, 6, 7, 0, 1, 2, 3},
        '{5, 4, 7, 6, 1, 0, 3, 2},
        '{6, 7, 4, 5, 2, 3, 0, 1},
        '{7, 6, 5, 4, 3, 2, 1, 0}
    };

    // 2. ADN de los Signos (1 = Negativo, 0 = Positivo)
    localparam logic M_NEG [0:DIMENSIONS-1][0:DIMENSIONS-1] = '{
        '{0, 1, 1, 1, 1, 1, 1, 1},
        '{0, 0, 0, 1, 0, 1, 1, 0},
        '{0, 1, 0, 0, 0, 0, 1, 1},
        '{0, 0, 1, 0, 0, 1, 0, 1},
        '{0, 1, 1, 1, 0, 0, 0, 0},
        '{0, 0, 1, 0, 1, 0, 1, 0},
        '{0, 0, 0, 1, 1, 0, 0, 1},
        '{0, 1, 0, 0, 1, 1, 0, 0}
    };

    // ---------------------------------------------------------------------
    // Ciclo 1: Enrutamiento combinacional (MUX) y Nivel 1 del Árbol
    // ---------------------------------------------------------------------
    logic signed [31:0] v_pos [0:DIMENSIONS-1];
    logic signed [31:0] v_neg [0:DIMENSIONS-1];
    logic signed [31:0] term  [0:DIMENSIONS-1][0:DIMENSIONS-1];
    logic signed [31:0] sum1  [0:DIMENSIONS-1][0:3];
    logic               valid_stg4_c1;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_stg4_c1 <= 1'b0;
        end else begin
            valid_stg4_c1 <= valid_stg3;
            if (valid_stg3) begin
                for (int i = 0; i < DIMENSIONS; i++) begin
                    v_pos[i] = Y_norm[i];
                    v_neg[i] = -Y_norm[i];
                end

                for (int r = 0; r < DIMENSIONS; r++) begin
                    for (int c = 0; c < DIMENSIONS; c++) begin
                        if (M_NEG[r][c] ^ trng_bits_delay[6][c]) begin
                            term[r][c] = v_neg[M_IDX[r][c]];
                        end else begin
                            term[r][c] = v_pos[M_IDX[r][c]];
                        end
                    end

                    sum1[r][0] <= term[r][0] + term[r][1];
                    sum1[r][1] <= term[r][2] + term[r][3];
                    sum1[r][2] <= term[r][4] + term[r][5];
                    sum1[r][3] <= term[r][6] + term[r][7];
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // Ciclo 2: Nivel 2 y 3 del Árbol (Salida Final)
    // ---------------------------------------------------------------------
    logic signed [31:0] sum2 [0:DIMENSIONS-1][0:1];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            for (int r = 0; r < DIMENSIONS; r++) m_out[r] <= '0;
        end else begin
            valid_out <= valid_stg4_c1;
            if (valid_stg4_c1) begin
                for (int r = 0; r < DIMENSIONS; r++) begin
                    sum2[r][0] = sum1[r][0] + sum1[r][1];
                    sum2[r][1] = sum1[r][2] + sum1[r][3];
                    m_out[r]  <= sum2[r][0] + sum2[r][1];
                end
            end
        end
    end

endmodule
