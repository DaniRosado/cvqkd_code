`timescale 1ns / 1ps

module mdr_alice_datapath (
    input  logic               clk,
    input  logic               rst_n,
    
    input  logic               valid_in,
    input  logic signed [15:0] X_in [0:7], 
    input  logic signed [31:0] m_in [0:7], 
    input  logic signed [31:0] K_dyn_in,   

    output logic               valid_out,
    output logic [7:0]         llr_out,    
    output logic [2:0]         llr_idx     
);

    localparam int M_IDX [0:7][0:7] = '{
        '{0, 1, 2, 3, 4, 5, 6, 7},
        '{1, 0, 3, 2, 5, 4, 7, 6},
        '{2, 3, 0, 1, 6, 7, 4, 5},
        '{3, 2, 1, 0, 7, 6, 5, 4},
        '{4, 5, 6, 7, 0, 1, 2, 3},
        '{5, 4, 7, 6, 1, 0, 3, 2},
        '{6, 7, 4, 5, 2, 3, 0, 1},
        '{7, 6, 5, 4, 3, 2, 1, 0}
    };
    localparam logic M_NEG [0:7][0:7] = '{
        '{0, 0, 0, 0, 0, 0, 0, 0},
        '{1, 0, 1, 0, 1, 0, 0, 1},
        '{1, 0, 0, 1, 1, 1, 0, 0},
        '{1, 1, 0, 0, 1, 0, 1, 0},
        '{1, 0, 0, 0, 0, 1, 1, 1},
        '{1, 1, 0, 1, 0, 0, 0, 1},
        '{1, 1, 1, 0, 0, 1, 0, 0},
        '{1, 0, 1, 1, 0, 0, 1, 0}
    };

    // (Mantén aquí arriba tus localparam M_IDX y M_NEG generados por MATLAB)

    // --- Registros de Captura ---
    logic signed [15:0] X_reg [0:7];
    logic signed [23:0] m_reg [0:7]; 
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
                    m_reg[i] <= m_in[i][26:3]; // Q24 -> Q21
                end
            end else if (computing) begin
                row_cnt <= row_cnt + 1;
                if (row_cnt == 3'd7) computing <= 1'b0;
            end
        end
    end

    // --- ETAPA 2: Los 8 Multiplicadores DSP48 y Tuberías de Retardo ---
    logic signed [41:0] mac_mult [0:7]; 
    logic signed [41:0] sum_lvl1 [0:3];
    logic signed [41:0] sum_lvl2 [0:1];
    logic signed [41:0] U_prime;
    
    logic               valid_u_prime;
    logic [2:0]         idx_u_prime;

    logic computing_d1, computing_d2, computing_d3;
    logic [2:0] row_cnt_d1, row_cnt_d2, row_cnt_d3;
    
    // LA MAGIA: Tubería de 4 ciclos para que K viaje junto a U_prime
    logic signed [31:0] K_reg_p1, K_reg_p2, K_reg_p3, K_reg_p4;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            computing_d1  <= 1'b0;
            computing_d2  <= 1'b0;
            computing_d3  <= 1'b0;
            valid_u_prime <= 1'b0;
            K_reg_p1      <= '0;
            K_reg_p2      <= '0;
            K_reg_p3      <= '0;
            K_reg_p4      <= '0;
        end else begin
            computing_d1  <= computing; 
            computing_d2  <= computing_d1;
            computing_d3  <= computing_d2;
            valid_u_prime <= computing_d3;
            
            // K avanza un paso en cada ciclo de reloj
            K_reg_p1      <= K_reg;
            K_reg_p2      <= K_reg_p1;
            K_reg_p3      <= K_reg_p2;
            K_reg_p4      <= K_reg_p3;
        end

        row_cnt_d1  <= row_cnt;   
        row_cnt_d2  <= row_cnt_d1;
        row_cnt_d3  <= row_cnt_d2;
        idx_u_prime <= row_cnt_d3;

        if (computing) begin
            for (int c = 0; c < 8; c++) begin
                if (M_NEG[row_cnt][c]) 
                    mac_mult[c] <= -$signed(18'(X_reg[ M_IDX[row_cnt][c] ])) * m_reg[c];
                else                   
                    mac_mult[c] <=  $signed(18'(X_reg[ M_IDX[row_cnt][c] ])) * m_reg[c];
            end
        end
        
        sum_lvl1[0] <= mac_mult[0] + mac_mult[1];
        sum_lvl1[1] <= mac_mult[2] + mac_mult[3];
        sum_lvl1[2] <= mac_mult[4] + mac_mult[5];
        sum_lvl1[3] <= mac_mult[6] + mac_mult[7];

        sum_lvl2[0] <= sum_lvl1[0] + sum_lvl1[1];
        sum_lvl2[1] <= sum_lvl1[2] + sum_lvl1[3];

        U_prime <= sum_lvl2[0] + sum_lvl2[1];
    end

    // --- Lógica Combinacional (Escalado de Salida Sincronizado) ---
    logic signed [73:0] llr_full; 
    logic signed [31:0] llr_int;
    
    always_comb begin
        // Usamos K_reg_p4, que ha llegado a la meta a la vez que U_prime
        llr_full = U_prime * K_reg_p4; 
        llr_int  = 32'(llr_full >>> 31);
    end

    // --- ETAPA 3: Saturación Signo-Magnitud ---
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            llr_out   <= '0;
            llr_idx   <= '0;
        end else begin
            valid_out <= valid_u_prime;
            llr_idx   <= idx_u_prime;

            if (valid_u_prime) begin
                if (llr_int > 127) begin
                    llr_out <= 8'd127;
                end else if (llr_int < -127) begin
                    llr_out <= 8'h80 | 8'd127; 
                end else if (llr_int < 0) begin
                    llr_out <= 8'h80 | 8'(-llr_int); 
                end else begin
                    llr_out <= 8'(llr_int);          
                end
            end
        end
    end

endmodule