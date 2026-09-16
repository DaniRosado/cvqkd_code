`timescale 1ns / 1ps

module mdr_bob_streaming (
    input  logic         clk,
    input  logic         rst_n,
    
    // --- Interfaz de Entrada (Directo desde el Acumulador) ---
    input  logic         valid_data, 
    input  logic [127:0] data_in,    // 8 dimensiones x 16 bits {Y8, Y7, Y6, Y5, Y4, Y3, Y2, Y1}
    input  logic [7:0]   trng_data,  // 8 bits aleatorios de la clave
    
    // --- Interfaz de Salida (Hacia el canal clásico / Alice) ---
    output logic         m_valid,    // Pulso a 1 cuando el mensaje está listo
    output logic [255:0] m_out       // Mensaje público: 8 x 32 bits {m8, m7, m6, m5, m4, m3, m2, m1}
);

    // =========================================================================
    // 1. CABLES INTERNOS
    // =========================================================================
    logic signed [15:0] Y_array [0:7];
    logic signed [31:0] m_array [0:7];

    // =========================================================================
    // 2. DESEMPAQUETADO (Deserialización)
    // =========================================================================
    // Cortamos el bus gigante de 128 bits que viene del Acumulador en 8 trozos
    // de 16 bits para que el Datapath los entienda.
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            Y_array[i] = data_in[(i*16) +: 16]; 
        end
    end

    // =========================================================================
    // 3. EMPAQUETADO (Serialización)
    // =========================================================================
    // Cogemos los 8 resultados de 32 bits del Datapath y los pegamos en un
    // único bus gigante de 256 bits para sacarlos del chip.
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            m_out[(i*32) +: 32] = m_array[i];
        end
    end

    // =========================================================================
    // 4. EL NÚCLEO MATEMÁTICO (Tu pipeline intacto)
    // =========================================================================
    // ¡Fíjate que no hay señales de done, ni de lectura/escritura de RAM!
    // Solo entran datos y salen datos al ritmo que marca valid_data.
    mdr_bob_datapath u_datapath (
        .clk       (clk),
        .rst_n     (rst_n),
        
        .valid_in  (valid_data),
        .Y_in      (Y_array),
        .trng_bits (trng_data),
        
        .valid_out (m_valid),
        .m_out     (m_array)
    );

endmodule