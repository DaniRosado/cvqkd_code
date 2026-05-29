`timescale 1ns / 1ps

module vnu_node (
    // --- Fase 1: Lectura y Resta (Hacia la CNU) ---
    input  logic [7:0] L_read,      // LLR total actual de la BRAM
    input  logic [7:0] R_old,       // Mensaje extrínseco viejo de la BRAM
    output logic [7:0] L_q,         // Información extrínseca que viaja a la CNU

    // --- Fase 2: Suma y Escritura (Desde la CNU) ---
    input  logic [7:0] L_q_delayed, // El mismo L_q, pero retrasado por el pipeline
    input  logic [7:0] R_new,       // Nuevo mensaje calculado por la CNU
    output logic [7:0] L_write      // Nuevo LLR total para guardar en BRAM
);

    // ==========================================
    // Funciones de Conversión (Sintetizables)
    // ==========================================
    
    // De Signo-Magnitud a Complemento a 2 (9 bits para no perder signo al sumar)
    function automatic logic signed [8:0] sm_to_2c(input logic [7:0] sm);
        logic signed [8:0] mag;
        mag = signed'({2'b00, sm[6:0]});
        return sm[7] ? -mag : mag;
    endfunction

    // De Complemento a 2 a Signo-Magnitud (con Saturación a +/- 127)
    function automatic logic [7:0] c2_to_sm_sat(input logic signed [8:0] val);
        logic signed [8:0] sat_val;
        logic [6:0] mag_out;
        logic sign_out;

        // Saturación
        if (val > 127)       sat_val = 9'sd127;
        else if (val < -127) sat_val = -9'sd127;
        else                 sat_val = val;

        // Conversión a SM
        if (sat_val < 0) begin
            sign_out = 1'b1;
            mag_out  = 7'(-sat_val);
        end else begin
            sign_out = 1'b0;
            mag_out  = 7'(sat_val);
        end
        
        return {sign_out, mag_out};
    endfunction

    // ==========================================
    // Lógica Combinacional (Cálculos)
    // ==========================================
    
    logic signed [8:0] L_read_2c, R_old_2c, L_q_2c;
    logic signed [8:0] L_q_delayed_2c, R_new_2c, L_write_2c;

    always_comb begin
        // Fase 1: L_q = L_read - R_old
        L_read_2c = sm_to_2c(L_read);
        R_old_2c  = sm_to_2c(R_old);
        L_q_2c    = L_read_2c - R_old_2c;
        L_q       = c2_to_sm_sat(L_q_2c);

        // Fase 2: L_write = L_q_delayed + R_new
        L_q_delayed_2c = sm_to_2c(L_q_delayed);
        R_new_2c       = sm_to_2c(R_new);
        L_write_2c     = L_q_delayed_2c + R_new_2c;
        L_write        = c2_to_sm_sat(L_write_2c);
    end

endmodule