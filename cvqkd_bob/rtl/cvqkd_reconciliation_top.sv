`timescale 1ns / 1ps

module cvqkd_reconciliation_top (
    input  logic         clk,
    input  logic         rst_n,

    // --- Interfaz de Entrada (Desde el Router / Divider) ---
    input  logic         router_valid,
    input  logic [31:0]  router_data, // Contiene {Q[15:0], P[15:0]}

    // --- Interfaz de Entrada (Desde el Generador Aleatorio TRNG) ---
    input  logic [7:0]   trng_data,   // Clave aleatoria de 8 bits

    // --- Interfaz de Salida 1: Hacia Alice (Canal Clásico) ---
    output logic         mdr_valid,
    output logic [255:0] mdr_m_out,   // Mensaje público m (8 dimensiones de 32 bits)

    // --- Interfaz de Salida 2: Hacia Procesador ARM (Síndrome LDPC) ---
    output logic         syndrome_done,
    output logic [383:0] syndrome_out [0:45]
);

    // =========================================================================
    // CABLES INTERNOS DE INTERCONEXIÓN
    // =========================================================================
    logic         accum_valid;
    logic [127:0] accum_data;

    // =========================================================================
    // 1. EL ACUMULADOR (Convierte 4 pulsos de 32 bits en 1 pulso de 128 bits)
    // =========================================================================
    mdr_accumulator u_accum (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (router_valid),
        .data_in   (router_data),
        .valid_data(accum_valid),
        .data_out  (accum_data)
    );

    // =========================================================================
    // 2. EL MOTOR MDR (Genera el mensaje para Alice)
    // =========================================================================
    mdr_bob_streaming u_mdr (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_data(accum_valid),   // Se dispara con el acumulador
        .data_in   (accum_data),
        .trng_data (trng_data),
        .m_valid   (mdr_valid),
        .m_out     (mdr_m_out)
    );

    // =========================================================================
    // 3. EL CÁLCULO DE SÍNDROME (Espía la clave y usa Ping-Pong)
    // =========================================================================
    cvqkd_syndrome_pingpong u_syndrome (
        .clk         (clk),
        .rst_n       (rst_n),
        .valid_data  (accum_valid), // Espía la misma señal que el MDR
        .trng_data   (trng_data),   // Captura los mismos 8 bits que usa el MDR
        .done        (syndrome_done),
        .syndrome_out(syndrome_out)
    );

endmodule