// ============================================================================
// Módulo:       mdr_bob_top
// Proyecto:     CV-QKD Hardware Accelerator
// Descripción:  Módulo top: interconecta FSM y Datapath MDR de Bob
// Dependencias: mdr_bob_pkg.sv, mdr_bob_fsm.sv, mdr_bob_datapath.sv
// ----------------------------------------------------------------------------
// Notas de Arquitectura:
// Diseño altamente pipelinizado (Latencia total: 9 ciclos datapath + flush FSM).
// ============================================================================

`timescale 1ns / 1ps

module mdr_bob_top (
    input  logic         clk,
    input  logic         rst_n,
    
    // --- Interfaz de Control ---
    input  logic         start,
    output logic         done,
    
    // --- Interfaz con el TRNG ---
    // (Asumimos que el TRNG escupe 8 bits aleatorios en cada ciclo de reloj)
    input  logic [7:0]   trng_data,
    
    // --- Interfaz con RAM de Lectura (Bob ADC Data) ---
    output logic         ram_read_en,
    output logic [13:0]  ram_read_addr,
    input  logic [127:0] ram_read_data, // 8 x 16-bits concatenados
    
    // --- Interfaz con RAM de Escritura (Mensaje m a Alice) ---
    output logic         ram_write_en,
    output logic [13:0]  ram_write_addr,
    output logic [255:0] ram_write_data // 8 x 32-bits concatenados (Q31)
);

    // --- Señales Internas de Interconexión ---
    logic               dp_valid_in;
    logic               dp_valid_out;
    logic signed [15:0] Y_array [0:7];
    logic signed [31:0] m_array [0:7];

    // 1. Desempaquetado de la lectura de memoria (128 bits -> 8 x 16 bits)
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            // Extraemos los bloques de 16 bits del bus gigante de la RAM
            Y_array[i] = ram_read_data[(i*16) +: 16]; 
        end
    end

    // 2. Empaquetado de la escritura de memoria (8 x 32 bits -> 256 bits)
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            ram_write_data[(i*32) +: 32] = m_array[i];
        end
    end

    // --- INSTANCIACIÓN DE LA FSM ---
    mdr_bob_fsm u_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .dp_valid_out    (dp_valid_out),
        
        .ram_read_en     (ram_read_en),
        .ram_read_addr   (ram_read_addr),
        .dp_valid_in     (dp_valid_in),
        
        .ram_write_en    (ram_write_en),
        .ram_write_addr  (ram_write_addr),
        .done            (done)
    );

    // --- INSTANCIACIÓN DEL DATAPATH ---
    mdr_bob_datapath u_datapath (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .valid_in        (dp_valid_in),
        .Y_in            (Y_array),
        .trng_bits       (trng_data),
        
        .valid_out       (dp_valid_out),
        .m_out           (m_array)
    );

endmodule