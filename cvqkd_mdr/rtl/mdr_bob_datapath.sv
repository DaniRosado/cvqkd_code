// ============================================================================
// Módulo:       mdr_bob_datapath
// Proyecto:     CV-QKD Hardware Accelerator
// Descripción:  Datapath pipelinizado: norma, raíz inversa LUT y matriz ortogonal
// Dependencias: mdr_rom_pkg.sv
// ----------------------------------------------------------------------------
// Notas de Arquitectura:
// m = M(u) · y / ||y||, con M la matriz ortogonal 8x8 de signos de la clave u.
// Latencia: 8 ciclos. Solo las señales de validez tienen reset: los registros de
// datos no lo necesitan, y así Vivado puede llevar las líneas de retardo a SRL y
// los productos a los registros internos de los DSP48.
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
    localparam int DELAY_STAGES = 6;  // Ciclos hasta que se usan y e u en las etapas 3 y 4

    // =====================================================================
    // ETAPA 1: SUMA DE CUADRADOS (Norma al cuadrado)
    // =====================================================================
    logic unsigned [31:0] Y_sq [0:DIMENSIONS-1];
    logic unsigned [32:0] sum_lvl1_0, sum_lvl1_1, sum_lvl1_2, sum_lvl1_3;  // 33 bits
    logic unsigned [33:0] sum_lvl2_0, sum_lvl2_1;                          // 34 bits
    logic unsigned [34:0] norm_sq;                                         // 35 bits
    logic                 valid_sq, valid_stg1;

    // Ciclo 1a: Multiplicadores (registrados)
    always_ff @(posedge clk) begin
        if (!rst_n) valid_sq <= 1'b0;
        else        valid_sq <= valid_in;
        if (valid_in) begin
            for (int i = 0; i < DIMENSIONS; i++) Y_sq[i] <= $unsigned( 32'(Y_in[i]) * 32'(Y_in[i]) );
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
        if (!rst_n) valid_stg1 <= 1'b0;
        else        valid_stg1 <= valid_sq;
        if (valid_sq) norm_sq <= sum_lvl2_0 + sum_lvl2_1;
    end

    // =====================================================================
    // ETAPA 2: LZC + SEMILLA ROM (Raíz inversa 1/sqrt(norm_sq))
    // =====================================================================
    // Ciclo 2a: Leading Zero Counter, normalización y dirección de la ROM
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

    assign norm_sq_shifted = norm_sq << lzc;

    always_ff @(posedge clk) begin
        if (!rst_n) valid_stg2_c1 <= 1'b0;
        else        valid_stg2_c1 <= valid_stg1;
        if (valid_stg1) begin
            rom_addr         <= {lzc[0], norm_sq_shifted[33:26]};
            final_shift_reg1 <= (6'd34 - lzc) >> 1;
        end
    end

    // Ciclo 2b: Lectura de la ROM de semillas
    logic [23:0] y0;
    logic [5:0]  final_shift_reg2;
    logic        valid_stg2_c2;

    always_ff @(posedge clk) begin
        if (!rst_n) valid_stg2_c2 <= 1'b0;
        else        valid_stg2_c2 <= valid_stg2_c1;
        if (valid_stg2_c1) begin
            y0               <= mdr_rom_pkg::INV_SQRT_ROM[rom_addr];
            final_shift_reg2 <= final_shift_reg1;
        end
    end

    // =====================================================================
    // LÍNEAS DE RETARDO (alineación de y y de los bits de clave con la tubería)
    // =====================================================================
    // Y_in_delay[k] y trng_bits_delay[k] contienen la entrada de hace k+1 ciclos
    logic signed [ADC_WIDTH-1:0] Y_in_delay [0:DELAY_STAGES-1][0:DIMENSIONS-1];
    logic [DIMENSIONS-1:0]       trng_bits_delay [0:DELAY_STAGES-1];

    always_ff @(posedge clk) begin
        for (int j = 0; j < DIMENSIONS; j++) Y_in_delay[0][j] <= Y_in[j];
        trng_bits_delay[0] <= trng_bits;
        for (int i = 1; i < DELAY_STAGES; i++) begin
            for (int j = 0; j < DIMENSIONS; j++) Y_in_delay[i][j] <= Y_in_delay[i-1][j];
            trng_bits_delay[i] <= trng_bits_delay[i-1];
        end
    end

    // =====================================================================
    // ETAPA 3: NORMALIZACIÓN (y * 1/||y||)
    // =====================================================================
    logic signed [40:0] Y_mult [0:DIMENSIONS-1];
    logic signed [31:0] Y_norm [0:DIMENSIONS-1];
    logic               valid_stg3_mult, valid_stg3;
    logic [5:0]         final_shift_reg3;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_stg3_mult <= 1'b0;
            valid_stg3      <= 1'b0;
        end else begin
            valid_stg3_mult <= valid_stg2_c2;
            valid_stg3      <= valid_stg3_mult;
        end
        // Ciclo 3a: Multiplicación por la semilla
        if (valid_stg2_c2) begin
            final_shift_reg3 <= final_shift_reg2;
            for (int i = 0; i < DIMENSIONS; i++) Y_mult[i] <= Y_in_delay[3][i] * $signed({1'b0, y0});
        end
        // Ciclo 3b: Desplazamiento y truncamiento
        if (valid_stg3_mult) begin
            for (int i = 0; i < DIMENSIONS; i++) Y_norm[i] <= 32'(Y_mult[i] >>> final_shift_reg3);
        end
    end

    // =====================================================================
    // ETAPA 4: MATRIZ ORTOGONAL (Generación del Mensaje Público)
    // =====================================================================
    // Índices de la matriz transpuesta y signos (1 = negativo)
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

    // Ciclo 4a: Enrutamiento con signo (bits de clave) y nivel 1 del árbol
    logic signed [31:0] term [0:DIMENSIONS-1][0:DIMENSIONS-1];
    logic signed [31:0] sum1 [0:DIMENSIONS-1][0:3];
    logic               valid_stg4_c1;

    always_comb begin
        for (int r = 0; r < DIMENSIONS; r++) begin
            for (int c = 0; c < DIMENSIONS; c++) begin
                term[r][c] = (M_NEG[r][c] ^ trng_bits_delay[5][c]) ? -Y_norm[M_IDX[r][c]]
                                                                   :  Y_norm[M_IDX[r][c]];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) valid_stg4_c1 <= 1'b0;
        else        valid_stg4_c1 <= valid_stg3;
        if (valid_stg3) begin
            for (int r = 0; r < DIMENSIONS; r++) begin
                sum1[r][0] <= term[r][0] + term[r][1];
                sum1[r][1] <= term[r][2] + term[r][3];
                sum1[r][2] <= term[r][4] + term[r][5];
                sum1[r][3] <= term[r][6] + term[r][7];
            end
        end
    end

    // Ciclo 4b: Niveles 2 y 3 del árbol (salida final)
    always_ff @(posedge clk) begin
        if (!rst_n) valid_out <= 1'b0;
        else        valid_out <= valid_stg4_c1;
        if (valid_stg4_c1) begin
            for (int r = 0; r < DIMENSIONS; r++) begin
                m_out[r] <= (sum1[r][0] + sum1[r][1]) + (sum1[r][2] + sum1[r][3]);
            end
        end
    end

endmodule
