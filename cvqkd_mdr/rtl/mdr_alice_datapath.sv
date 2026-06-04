`timescale 1ns / 1ps

module mdr_alice_datapath (
    input  logic               clk,
    input  logic               rst_n,
    
    // --- Interfaz de Entrada (Llega 1 bloque cada 8 ciclos) ---
    input  logic               valid_in,
    input  logic signed [15:0] X_in [0:7], // Datos crudos ADC de Alice
    input  logic signed [31:0] m_in [0:7], // Mensaje de Bob (Q24)
    input  logic signed [31:0] K_dyn_in,   // Factor del ARM (Q10)

    // --- Interfaz de Salida (Escupe 1 LLR por ciclo de reloj) ---
    output logic               valid_out,
    output logic [7:0]         llr_out,    // Formato Signo-Magnitud
    output logic [2:0]         llr_idx     // Indica qué dimensión (0-7) está saliendo
);

    // Mismo ADN de matriz que en Bob
    localparam int M_IDX [0:7][0:7] = '{
        '{0, 1, 2, 3, 4, 5, 6, 7}, '{1, 0, 3, 2, 5, 4, 7, 6},
        '{2, 3, 0, 1, 6, 7, 4, 5}, '{3, 2, 1, 0, 7, 6, 5, 4},
        '{4, 5, 6, 7, 0, 1, 2, 3}, '{5, 4, 7, 6, 1, 0, 3, 2},
        '{6, 0, 0, 1, 1, 0, 0, 1}, '{0, 1, 0, 0, 1, 1, 0, 0} // Usar tu matriz corregida aquí
    };

    localparam logic M_NEG [0:7][0:7] = '{
        '{0, 1, 1, 1, 1, 1, 1, 1}, '{0, 0, 0, 1, 0, 1, 1, 0},
        '{0, 1, 0, 0, 0, 0, 1, 1}, '{0, 0, 1, 0, 0, 1, 0, 1},
        '{0, 1, 1, 1, 0, 0, 0, 0}, '{0, 0, 1, 0, 1, 0, 1, 0},
        '{0, 0, 0, 1, 1, 0, 0, 1}, '{0, 1, 0, 0, 1, 1, 0, 0}
    };

    // --- Registros de Captura ---
    logic signed [15:0] X_reg [0:7];
    logic signed [23:0] m_reg [0:7]; // Truncamos a 24b para forzar 1 solo DSP48
    logic signed [31:0] K_reg;
    logic [2:0]         row_cnt;
    logic               computing;

    // --- ETAPA 1: Máquina de Estados MAC ---
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            computing <= 1'b0;
            row_cnt   <= '0;
        end else begin
            if (valid_in) begin
                computing <= 1'b1;
                row_cnt   <= '0;
                K_reg     <= K_dyn_in;
                for (int i=0; i<8; i++) begin
                    X_reg[i] <= X_in[i];
                    m_reg[i] <= m_in[i][23:0]; 
                end
            end else if (computing) begin
                row_cnt <= row_cnt + 1;
                if (row_cnt == 3'd7) computing <= 1'b0; // Apagamos tras 8 ciclos
            end
        end
    end

    // --- ETAPA 2: Los 8 Multiplicadores DSP48 (Pipelined) ---
    logic signed [17:0] x_coef;
    logic signed [41:0] mac_mult [0:7]; // Q0 * Q24 = Q24
    logic signed [41:0] sum_lvl1 [0:3];
    logic signed [41:0] sum_lvl2 [0:1];
    logic signed [41:0] U_prime;
    logic               valid_u_prime;
    logic [2:0]         idx_u_prime;

    // Pipeline delay signals
    logic computing_d1, computing_d2;
    logic [2:0] row_cnt_d1, row_cnt_d2;

    always_ff @(posedge clk) begin
        // Retardos de sincronización
        computing_d1 <= computing; computing_d2 <= computing_d1;
        row_cnt_d1   <= row_cnt;   row_cnt_d2   <= row_cnt_d1;
        valid_u_prime <= computing_d2;
        idx_u_prime   <= row_cnt_d2;

        if (computing) begin
            // 1. Asignación combinacional de MUX
            for (int c = 0; c < 8; c++) begin
                if (M_NEG[row_cnt][c]) x_coef = -X_reg[ M_IDX[row_cnt][c] ];
                else                   x_coef =  X_reg[ M_IDX[row_cnt][c] ];
                
                // Multiplicación nativa para Vivado DSP (18b x 24b)
                mac_mult[c] <= $signed(x_coef) * m_reg[c];
            end
        end
        
        // 2. Árbol de Sumas (Ciclo extra de pipeline para cerrar timing a tope)
        sum_lvl1[0] <= mac_mult[0] + mac_mult[1];
        sum_lvl1[1] <= mac_mult[2] + mac_mult[3];
        sum_lvl1[2] <= mac_mult[4] + mac_mult[5];
        sum_lvl1[3] <= mac_mult[6] + mac_mult[7];

        sum_lvl2[0] <= sum_lvl1[0] + sum_lvl1[1];
        sum_lvl2[1] <= sum_lvl1[2] + sum_lvl1[3];

        U_prime <= sum_lvl2[0] + sum_lvl2[1];
    end

    // --- ETAPA 3: Escalado K y Saturación Signo-Magnitud ---
    logic signed [73:0] llr_full; // Q24 * Q10 = Q34
    logic signed [31:0] llr_int;  // Parte entera

    always_ff @(posedge clk) begin
        valid_out <= valid_u_prime;
        llr_idx   <= idx_u_prime;

        if (valid_u_prime) begin
            // Multiplicamos por K_dyn
            llr_full = U_prime * K_reg;
            
            // Truncamos la parte fraccional (34 bits) para quedarnos con el entero
            llr_int = 32'(llr_full >>> 34);

            // Saturación a +/- 127
            if (llr_int > 127)       llr_int = 127;
            else if (llr_int < -127) llr_int = -127;

            // Formateo a Signo-Magnitud (8 bits)
            if (llr_int < 0) begin
                llr_out <= 8'h80 | 8'(-llr_int); // Ponemos el bit 7 a '1'
            end else begin
                llr_out <= 8'(llr_int);          // El bit 7 se queda a '0'
            end
        end
    end

endmodule