`timescale 1ns / 1ps

// ============================================================================
// VNU con LLR a posteriori más ancho que los mensajes.
// Si el posterior L tuviera el mismo rango que los mensajes R, al saturarse
// L_q = L - R_old perdería la confianza acumulada y el decodificador layered
// se desestabilizaría tras converger. Con WL > W, L no se satura en la práctica
// y solo se satura la copia de L_q que va hacia la CNU.
// ============================================================================
module vnu_node #(
    parameter int W  = 8,   // Mensajes R y L_q hacia la CNU (signo-magnitud)
    parameter int WL = 10   // LLR a posteriori guardado en L_BRAM (signo-magnitud)
)(
    // --- Fase 1: Lectura y Resta (Hacia la CNU) ---
    input  logic [WL-1:0]      L_read,           // LLR total actual de la BRAM
    input  logic [W-1:0]       R_old,            // Mensaje extrínseco viejo de la BRAM
    output logic [W-1:0]       L_q,              // Extrínseco hacia la CNU (saturado a W bits)
    output logic signed [WL:0] L_q_full,         // Extrínseco exacto (camino de escritura)

    // --- Fase 2: Suma y Escritura (Desde la CNU) ---
    input  logic signed [WL:0] L_q_full_delayed, // L_q_full retrasado por el pipeline
    input  logic [W-1:0]       R_new,            // Nuevo mensaje calculado por la CNU
    output logic [WL-1:0]      L_write           // Nuevo LLR total para guardar en BRAM
);

    localparam int Q_MAX = (1 << (W-1)) - 1;   // 127 con W = 8
    localparam int L_MAX = (1 << (WL-1)) - 1;  // 511 con WL = 10

    // Signo-magnitud a complemento a 2 (WL+2 bits: cabe |L| + |R| sin desbordar)
    function automatic logic signed [WL+1:0] sm_to_2c(input logic sign, input logic [WL-2:0] mag);
        return sign ? -$signed({2'b00, mag}) : $signed({2'b00, mag});
    endfunction

    // Complemento a 2 a signo-magnitud de WL bits con saturación a +/- max_mag
    function automatic logic [WL-1:0] sat_to_sm(input logic signed [WL+1:0] val, input int max_mag);
        logic signed [WL+1:0] sat;
        if (val > max_mag)       sat = max_mag;
        else if (val < -max_mag) sat = -max_mag;
        else                     sat = val;
        return (sat < 0) ? {1'b1, (WL-1)'(-sat)} : {1'b0, (WL-1)'(sat)};
    endfunction

    logic [WL-1:0] L_q_sm;

    always_comb begin
        // Fase 1: L_q = L_read - R_old (exacto) y su copia saturada para la CNU
        L_q_full = (WL+1)'(sm_to_2c(L_read[WL-1], L_read[WL-2:0])
                         - sm_to_2c(R_old[W-1], (WL-1)'(R_old[W-2:0])));
        L_q_sm   = sat_to_sm((WL+2)'(L_q_full), Q_MAX);
        L_q      = {L_q_sm[WL-1], L_q_sm[W-2:0]};

        // Fase 2: L_write = L_q + R_new, saturado al rango del posterior
        L_write  = sat_to_sm((WL+2)'(L_q_full_delayed) + sm_to_2c(R_new[W-1], (WL-1)'(R_new[W-2:0])),
                             L_MAX);
    end

endmodule
