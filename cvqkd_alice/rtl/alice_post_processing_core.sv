`timescale 1ns / 1ps

// ============================================================================
// Módulo:       alice_post_processing_core
// Proyecto:     CV-QKD Hardware Accelerator
// Descripción:  Subsistema completo de Alice. Encapsula la Reconciliación 
//               Multidimensional (MDR) y la Decodificación LDPC, unidos por
//               un adaptador Serie-Paralelo.
// ============================================================================

module alice_post_processing_core #(
    parameter int Z = 384,
    parameter int W = 8,
    parameter int BUS_WIDTH = Z * W, // 3072 bits
    parameter int TOTAL_BLOCKS = 3264
)(
    input  logic         clk,
    input  logic         rst_n,
    
    // --- Control Global ---
    input  logic         start_mdr,      // Inicia la ingesta de datos crudos
    input  logic         start_ldpc,     // Inicia la decodificación tras la carga
    output logic         mdr_done,       // El MDR ha terminado de procesar
    output logic         ldpc_done,      // El LDPC ha terminado
    output logic         ldpc_success,   // 1 = Clave corregida, 0 = Fallo
    
    // --- Interfaz de Entrada (ADC y Red) -> Hacia MDR ---
    output logic         ram_x_en,
    output logic [13:0]  ram_x_addr,
    input  logic [127:0] ram_x_data,     // Coordenadas X crudas
    input  logic [255:0] ram_m_data,     // Mensaje m de Bob
    input  logic [31:0]  ram_k_data      // Constante K del ARM
);

    // =====================================================================
    // 1. CABLES INTERNOS DE INTERCONEXIÓN
    // =====================================================================
    
    // Salidas del MDR
    logic        mdr_write_en;
    logic [16:0] mdr_write_addr; 
    logic [7:0]  mdr_write_data;

    // Entradas del LDPC (Generadas por el adaptador)
    logic                 ldpc_load_en;
    logic [6:0]           ldpc_load_addr;
    logic [BUS_WIDTH-1:0] ldpc_load_data;

    // =====================================================================
    // 2. INSTANCIACIÓN DEL MDR (Generador de LLRs)
    // =====================================================================
    mdr_alice_top # (
        .TOTAL_BLOCKS(TOTAL_BLOCKS)
    )u_MDR (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start_mdr),
        .done            (mdr_done),
        
        .ram_x_en        (ram_x_en),
        .ram_x_addr      (ram_x_addr),
        .ram_x_data      (ram_x_data),
        .ram_m_data      (ram_m_data),
        .ram_k_data      (ram_k_data),
        
        // Salida Streaming de 8 bits
        .ram_write_en    (mdr_write_en),
        .ram_write_addr  (mdr_write_addr),
        .ram_write_data  (mdr_write_data)
    );

    // =====================================================================
    // 3. ADAPTADOR SERIE-PARALELO (8 bits -> 3072 bits)
    // =====================================================================
    // Acumula Z (384) LLRs y lanza un pulso de escritura al LDPC
    
    logic [8:0] llr_counter; // Cuenta de 0 a 383
    logic [6:0] row_counter; // Cuenta las filas del LDPC llenadas
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            llr_counter    <= '0;
            row_counter    <= '0;
            ldpc_load_en   <= 1'b0;
            ldpc_load_addr <= '0;
            ldpc_load_data <= '0;
        end else begin
            ldpc_load_en <= 1'b0; // Por defecto apagado (pulso de 1 ciclo)
            
            if (start_mdr) begin
                // Reiniciamos los contadores si empieza un bloque nuevo
                llr_counter <= '0;
                row_counter <= '0;
            end else if (mdr_write_en) begin
                // Empaquetamos el LLR de 8 bits en la posición correcta del bus gigante
                // usando indexación dinámica (+: 8)
                ldpc_load_data[(llr_counter * W) +: W] <= mdr_write_data;
                
                if (llr_counter == Z - 1) begin
                    // La caja está llena: disparamos escritura hacia el LDPC
                    llr_counter    <= '0;
                    ldpc_load_en   <= 1'b1;
                    ldpc_load_addr <= row_counter;
                    row_counter    <= row_counter + 1;
                end else begin
                    llr_counter <= llr_counter + 1;
                end
            end
        end
    end

    // =====================================================================
    // 4. CONTROL DE ESTADO Y DECODIFICADOR LDPC
    // =====================================================================
    
    // Registro que mantiene vivo el modo decodificación hasta que termina
    logic is_decoding;
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            is_decoding <= 1'b0;
        end else if (start_ldpc) begin
            is_decoding <= 1'b1;  // Arranca el LDPC, bloqueamos la carga externa
        end else if (ldpc_done) begin
            is_decoding <= 1'b0;  // Termina el LDPC, volvemos a modo escucha
        end
    end

    ldpc_decoder_top #(
        .Z(Z), 
        .W(W), 
        .PIPELINE_DEPTH(3)
    ) u_LDPC (
        .clk              (clk),
        .rst_n            (rst_n),
        
        .start_decoding   (start_ldpc),
        .decoding_done    (ldpc_done),
        .decoding_success (ldpc_success),
        
        // Interfaz de Carga (Ahora sí, gobernada por el estado real)
        .load_mode        (~is_decoding), 
        .load_write_en    (ldpc_load_en),
        .load_write_addr  (ldpc_load_addr),
        .load_write_data  (ldpc_load_data)
    );

endmodule