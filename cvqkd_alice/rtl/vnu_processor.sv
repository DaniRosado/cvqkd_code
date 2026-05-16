`timescale 1ns / 1ps

module vnu_processor #(
    parameter int W = 8  // Ancho del dato (1 bit signo + 7 bits magnitud)
)(
    input  logic         clk,
    input  logic         rst_n,
    
    // Entradas en formato Signo-Magnitud
    input  logic [W-1:0] p_n_in,      // LLR Total actual del nodo (desde la RAM)
    input  logic [W-1:0] r_old_in,    // Mensaje viejo de la CNU (desde la RAM)
    input  logic [W-1:0] r_new_in,    // Mensaje nuevo de la CNU (recién calculado)
    
    // Salidas
    output logic [W-1:0] q_mn_out,    // Mensaje hacia la CNU (Signo-Magnitud)
    output logic [W-1:0] p_n_out,     // Nuevo LLR Total para guardar en RAM (Signo-Magnitud)
    output logic         hard_decision // Bit decodificado final
);

    // =========================================================================
    // Funciones auxiliares de conversión
    // =========================================================================
    function automatic logic signed [W-1:0] sm_to_c2(input logic [W-1:0] sm_val);
        // De Signo-Magnitud a Complemento a 2
        logic sign;
        logic [W-2:0] mag;
        sign = sm_val[W-1];
        mag  = sm_val[W-2:0];
        return sign ? -signed'({1'b0, mag}) : signed'({1'b0, mag});
    endfunction

    function automatic logic [W-1:0] c2_to_sm(input logic signed [W-1:0] c2_val);
        // De Complemento a 2 a Signo-Magnitud
        logic sign;
        logic [W-2:0] mag;
        sign = c2_val[W-1];
        mag  = sign ? -c2_val[W-2:0] : c2_val[W-2:0];
        // Saturación manual por si el valor es el negativo extremo
        if (sign && c2_val[W-2:0] == '0) mag = '1; 
        return {sign, mag};
    endfunction

    // =========================================================================
    // 1. Conversión de Entradas a Complemento a 2
    // =========================================================================
    logic signed [W-1:0] p_n_c2;
    logic signed [W-1:0] r_old_c2;
    logic signed [W-1:0] r_new_c2;
    
    assign p_n_c2   = sm_to_c2(p_n_in);
    assign r_old_c2 = sm_to_c2(r_old_in);
    assign r_new_c2 = sm_to_c2(r_new_in);

    // =========================================================================
    // 2. Aritmética con Saturación (Evitar Overflows)
    // =========================================================================
    // Usamos un bit extra (W) para capturar el desbordamiento
    logic signed [W:0] q_mn_ext;
    logic signed [W:0] p_n_new_ext;
    
    logic signed [W-1:0] q_mn_sat;
    logic signed [W-1:0] p_n_new_sat;
    
    // Límites de saturación para Complemento a 2
    localparam logic signed [W:0] MAX_VAL = (1 << (W-1)) - 1;
    localparam logic signed [W:0] MIN_VAL = -(1 << (W-1));

    always_comb begin
        // A. Cálculo del mensaje extrínseco (Hacia la CNU)
        q_mn_ext = p_n_c2 - r_old_c2;
        
        // Saturación Q_mn
        if (q_mn_ext > MAX_VAL)      q_mn_sat = MAX_VAL[W-1:0];
        else if (q_mn_ext < MIN_VAL) q_mn_sat = MIN_VAL[W-1:0];
        else                         q_mn_sat = q_mn_ext[W-1:0];

        // B. Actualización del LLR Total (Se guarda en memoria)
        p_n_new_ext = q_mn_sat + r_new_c2;
        
        // Saturación P_n_new
        if (p_n_new_ext > MAX_VAL)      p_n_new_sat = MAX_VAL[W-1:0];
        else if (p_n_new_ext < MIN_VAL) p_n_new_sat = MIN_VAL[W-1:0];
        else                            p_n_new_sat = p_n_new_ext[W-1:0];
    end

    // =========================================================================
    // 3. Conversión de Salida y Hard Decision
    // =========================================================================
    assign q_mn_out = c2_to_sm(q_mn_sat);
    assign p_n_out  = c2_to_sm(p_n_new_sat);
    
    // El bit decodificado es simplemente el signo del LLR total en c2
    // Si es positivo (0) -> bit 0. Si es negativo (1) -> bit 1.
    assign hard_decision = (p_n_new_sat < 0) ? 1'b1 : 1'b0;

endmodule