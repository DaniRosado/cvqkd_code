`timescale 1ns / 1ps

// ============================================================================
// Módulo:       mdr_alice_top
// Proyecto:     CV-QKD Hardware Accelerator
// Descripción:  Módulo Top-Level para la reconciliación de Alice. Cooridna
//               la FSM de control y el Datapath con motor MAC plegado (8 ciclos).
// Dependencias: mdr_alice_fsm.sv, mdr_alice_datapath.sv
// ============================================================================

module mdr_alice_top (
    input  logic         clk,
    input  logic         rst_n,
    
    // --- Interfaz de Control ---
    input  logic         start,
    output logic         done,
    
    // --- Interfaz con RAM de Lectura (Coordenadas X crudas de Alice) ---
    output logic         ram_x_en,
    output logic [13:0]  ram_x_addr,
    input  logic [127:0] ram_x_data,     // 8 x 16-bits crudos concatenados
    
    // --- Interfaz con RAM de Lectura (Mensajes m recibidos de Bob) ---
    // (Comparten el mismo direccionamiento que las X ya que van bloque a bloque)
    input  logic [255:0] ram_m_data,     // 8 x 32-bits (Q24) concatenados
    
    // --- Interfaz con RAM de Lectura (Constante K dinámica del ARM) ---
    input  logic [31:0]  ram_k_data,     // 32-bits (Q10)
    
    // --- Interfaz de Salida Streaming (Hacia la L_BRAM del LDPC) ---
    output logic         ram_write_en,
    output logic [16:0]  ram_write_addr, // 17 bits para direccionar 104448 LLRs
    output logic [7:0]   ram_write_data  // LLR final en Signo-Magnitud
);

    // --- Cables Internos de Interconexión ---
    logic               dp_valid_in;
    logic               dp_valid_out;
    logic [7:0]         dp_llr_out;
    logic [2:0]         dp_llr_idx;

    logic signed [15:0] X_array [0:7];
    logic signed [31:0] m_array [0:7];
    
    // Puntero de escritura secuencial para los LLRs
    logic [16:0]        waddr_reg;

    // =====================================================================
    // 1. DESEMPAQUETADO DE BUSES DE ENTRADA
    // =====================================================================
    // Convertimos los buses planos de las memorias RAM en arrays desempaquetados
    // listos para que los triture el Datapath.
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            X_array[i] = ram_x_data[(i*16) +: 16]; 
            m_array[i] = ram_m_data[(i*32) +: 32];
        end
    end

    // =====================================================================
    // 2. CONTROL DEL PUNTERO DE ESCRITURA (L_BRAM)
    // =====================================================================
    // El contador avanza estrictamente cuando el Datapath avisa que tiene
    // un LLR válido listo en su salida. Se reinicia con cada pulso de 'start'.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            waddr_reg <= '0;
        end else if (start) begin
            waddr_reg <= '0; 
        end else if (dp_valid_out) begin
            waddr_reg <= waddr_reg + 1;
        end
    end

    // Asignación directa de los puertos de salida hacia la memoria LDPC
    assign ram_write_addr = waddr_reg;
    assign ram_write_en   = dp_valid_out;
    assign ram_write_data = dp_llr_out;

    // =====================================================================
    // 3. INSTANCIACIÓN DE LOS SUBMÓDULOS
    // =====================================================================
    
    // El Cerebro: Dicta el ritmo de carga (1 bloque cada 8 ciclos de reloj)
    mdr_alice_fsm u_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        
        .ram_read_en     (ram_x_en),
        .ram_read_addr   (ram_x_addr),
        .dp_valid_in     (dp_valid_in),
        
        .done            (done)
    );

    // Los Músculos: Multiplicadores DSP48 trabajando en modo plegado
    mdr_alice_datapath u_datapath (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .valid_in        (dp_valid_in),
        .X_in            (X_array),
        .m_in            (m_array),
        .K_dyn_in        (ram_k_data),
        
        .valid_out       (dp_valid_out),
        .llr_out         (dp_llr_out),
        .llr_idx         (dp_llr_idx) // (Opcional si necesitas saber la dimensión en el destino)
    );

endmodule