`timescale 1ns / 1ps

// ============================================================================
// Módulo:       tb_alice_post_processing_core
// Proyecto:     CV-QKD Hardware Accelerator
// Descripción:  Testbench de integración a nivel de subsistema. Verifica la 
//               interacción perfecta entre el motor MDR y el decodificador LDPC.
// ============================================================================

module tb_alice_post_processing_core();

    // =====================================================================
    // 1. PARÁMETROS GLOBALES Y SEÑALES
    // =====================================================================
    localparam int TOTAL_BLOCKS = 3264; 
    localparam int CLK_PERIOD   = 10; // Frecuencia de 100 MHz

    // Reloj y Reset
    logic clk;
    logic rst_n;
    
    // Control del Procesador Virtual (El Testbench)
    logic start_mdr;
    logic start_ldpc;
    
    // Banderas de Estado del Subsistema
    logic mdr_done;
    logic ldpc_done;
    logic ldpc_success;

    // Buses de Memoria de Entrada
    logic         ram_x_en;
    logic [13:0]  ram_x_addr;
    logic [127:0] ram_x_data;
    logic [255:0] ram_m_data;
    logic [31:0]  ram_k_data;

    // =====================================================================
    // 2. EMULACIÓN DE MEMORIAS EXTERNAS (DDR / BRAM del ARM)
    // =====================================================================
    logic [127:0] ram_x_mem [0:TOTAL_BLOCKS-1];
    logic [255:0] ram_m_mem [0:TOTAL_BLOCKS-1];
    logic [31:0]  ram_k_mem [0:TOTAL_BLOCKS-1];

    initial begin
        // Cargamos la "Verdad Absoluta" exportada desde MATLAB
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/alice_mdr_inputs.txt",    ram_x_mem);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_m_messages.txt", ram_m_mem); // Lo que llegó de Bob
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/alice_k_dynamic.txt",     ram_k_mem);
        
        $display("---------------------------------------------------");
        $display("[TB-CORE] Archivos de entrada cargados en memoria externa.");
        $display("---------------------------------------------------");
    end

    // Respuesta combinacional de las memorias simuladas
    always_comb begin
        if (ram_x_en) begin
            ram_x_data = ram_x_mem[ram_x_addr];
            ram_m_data = ram_m_mem[ram_x_addr];
            ram_k_data = ram_k_mem[ram_x_addr];
        end else begin
            ram_x_data = '0;
            ram_m_data = '0;
            ram_k_data = '0;
        end
    end

    // =====================================================================
    // 3. INSTANCIACIÓN DEL SUBSISTEMA DE ALICE (DUT)
    // =====================================================================
    alice_post_processing_core u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        
        // Interfaz de Control
        .start_mdr        (start_mdr),
        .start_ldpc       (start_ldpc),
        .mdr_done         (mdr_done),
        .ldpc_done        (ldpc_done),
        .ldpc_success     (ldpc_success),
        
        // Interfaz de Memoria
        .ram_x_en         (ram_x_en),
        .ram_x_addr       (ram_x_addr),
        .ram_x_data       (ram_x_data),
        .ram_m_data       (ram_m_data),
        .ram_k_data       (ram_k_data)
    );

    // =====================================================================
    // 4. GENERACIÓN DE RELOJ Y SECUENCIA DE ESTÍMULOS
    // =====================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        // --- 4.1 Inicialización ---
        rst_n      = 0;
        start_mdr  = 0;
        start_ldpc = 0;
        
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);
        
        // --- 4.2 Fase 1: Extracción de LLRs (Reconciliación Multidimensional) ---
        $display("[TB-CORE] Iniciando Fase 1: Extracción de Información Cuántica (MDR)...");
        start_mdr = 1;
        #(CLK_PERIOD);
        start_mdr = 0;
        
        // Esperamos a que el Datapath purificado y la FSM procesen los 13056 bloques
        wait(mdr_done == 1'b1);
        $display("[TB-CORE] Fase 1 Completada. %0d Bloques procesados. L_BRAM llena.", TOTAL_BLOCKS);
        
        #(CLK_PERIOD * 10); // Pausa realista simulando la latencia del procesador
        
        // --- 4.3 Fase 2: Corrección de Errores (Decodificación LDPC) ---
        $display("[TB-CORE] Iniciando Fase 2: Corrección de Errores (Decodificador LDPC)...");
        start_ldpc = 1;
        #(CLK_PERIOD);
        start_ldpc = 0;
        
        // Esperamos a que la matriz converja o se rinda tras el límite de iteraciones
        wait(ldpc_done == 1'b1);
        
        // --- 4.4 Veredicto Final ---
        $display("---------------------------------------------------");
        if (ldpc_success == 1'b1) begin
            $display("  [!!!] ÉXITO ABSOLUTO: El LDPC ha convergido. ");
            $display("        Las claves de Alice y Bob son ahora idénticas.");
        end else begin
            $display("  [XXX] FALLO: El decodificador ha agotado las iteraciones ");
            $display("        sin alcanzar un síndrome válido. Clave descartada.");
        end
        $display("---------------------------------------------------");
        
        $finish;
    end

endmodule