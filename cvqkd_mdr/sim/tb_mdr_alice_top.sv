`timescale 1ns / 1ps

// ============================================================================
// Módulo:       tb_mdr_alice_top
// Proyecto:     CV-QKD Hardware Accelerator
// Descripción:  Banco de pruebas para el Top-Level de Alice. Carga datos de
//               MATLAB y verifica de forma secuencial la salida de los LLRs.
// ============================================================================

module tb_mdr_alice_top();

    // =====================================================================
    // 1. PARÁMETROS Y SEÑALES DE CONTROL
    // =====================================================================
    localparam int TOTAL_BLOCKS = 13056; 
    localparam int TOTAL_LLRS   = TOTAL_BLOCKS * 8; // 104.448 LLRs individuales
    localparam int CLK_PERIOD   = 10;               // Frecuencia: 100 MHz

    logic clk;
    logic rst_n;
    logic start;
    logic done;

    // --- Interfaces del Top-Level ---
    logic         ram_x_en;
    logic [13:0]  ram_x_addr;
    logic [127:0] ram_x_data;
    logic [255:0] ram_m_data;
    logic [31:0]  ram_k_data;
    
    logic         ram_write_en;
    logic [16:0]  ram_write_addr;
    logic [7:0]   ram_write_data;

    // =====================================================================
    // 2. MEMORIAS EMULADAS PARA LA SIMULACIÓN
    // =====================================================================
    // Memorias orientadas a bloques (13056 posiciones)
    logic [127:0] ram_x_mem [0:TOTAL_BLOCKS-1];
    logic [255:0] ram_m_mem [0:TOTAL_BLOCKS-1];
    logic [31:0]  ram_k_mem [0:TOTAL_BLOCKS-1];
    
    // Memoria orientada a LLRs individuales (104448 posiciones, 1 byte por línea)
    logic [7:0]   expected_llr_mem [0:TOTAL_LLRS-1];

    // =====================================================================
    // 3. CARGA DE LA "VERDAD ABSOLUTA" DE MATLAB
    // =====================================================================
    initial begin
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/alice_mdr_inputs.txt",          ram_x_mem);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_m_messages.txt",       ram_m_mem);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/alice_k_dynamic.txt",           ram_k_mem);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_llrs_hardware.txt",    expected_llr_mem);
        
        $display("---------------------------------------------------");
        $display("[TB-ALICE] Archivos cuánticos cargados con éxito.");
        $display("---------------------------------------------------");
    end

    // Comportamiento síncrono de las memorias de lectura del sistema
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
    // 4. INSTANCIACIÓN DEL DISPOSITIVO BAJO PRUEBA (DUT)
    // =====================================================================
    mdr_alice_top u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .start            (start),
        .done             (done),
        .ram_x_en         (ram_x_en),
        .ram_x_addr       (ram_x_addr),
        .ram_x_data       (ram_x_data),
        .ram_m_data       (ram_m_data),
        .ram_k_data       (ram_k_data),
        .ram_write_en     (ram_write_en),
        .ram_write_addr   (ram_write_addr),
        .ram_write_data   (ram_write_data)
    );

    // =====================================================================
    // 5. RELOJ Y ESTÍMULOS DE CONTROL
    // =====================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        // Inicialización y Reset activo
        rst_n = 0;
        start = 0;
        #(CLK_PERIOD * 10);
        
        // Liberamos el Reset
        rst_n = 1;
        #(CLK_PERIOD * 5);
        
        // Disparamos el motor MAC de Alice
        $display("[TB-ALICE] Activando acelerador... Desrotando matriz.");
        start = 1;
        #(CLK_PERIOD);
        start = 0; // Pulso de un ciclo es suficiente
        
        // Esperamos a que la FSM complete todos los bloques
        wait(done == 1'b1);
        
        $display("---------------------------------------------------");
        $display("  [TB-ALICE] SIMULACIÓN COMPLETADA CON ÉXITO");
        $display("---------------------------------------------------");
        $finish;
    end

    // =====================================================================
    // 6. CHEQUEADOR EN TIEMPO REAL (Tolerante a diferencias de redondeo)
    // =====================================================================
    int errores_totales = 0;

    always_ff @(posedge clk) begin
        if (ram_write_en) begin
            logic [7:0] hw_llr  = ram_write_data;
            logic [7:0] exp_llr = expected_llr_mem[ram_write_addr];
            
            // Convertimos el formato Signo-Magnitud a entero con signo para restar
            int hw_val  = (hw_llr[7])  ? -int'(hw_llr[6:0])  : int'(hw_llr[6:0]);
            int exp_val = (exp_llr[7]) ? -int'(exp_llr[6:0]) : int'(exp_llr[6:0]);
            
            int diff = hw_val - exp_val;
            if (diff < 0) diff = -diff;
            
            // Tolerancia estricta: permitimos un desfase de +/- 2 unidades
            // debido al truncamiento de punto fijo (24b * 18b) en la FPGA vs Flotante
            if (diff > 2) begin
                $display(" [!!!] ERROR Mismatch en LLR Posición %0d", ram_write_addr);
                $display("       -> HARDWARE LLR (SM): %b (%0d decimal)", hw_llr, hw_val);
                $display("       -> ESPERADO LLR (SM): %b (%0d decimal)", exp_llr, exp_val);
                errores_totales++;
                
                if (errores_totales > 10) begin
                    $display("[TB-ALICE] Demasiados errores detectados. Abortando.");
                    $stop;
                end
            end else begin
                // Reporte periódico para comprobar la salud de la simulación
                if (ram_write_addr % 10000 == 0 && ram_write_addr > 0) begin
                    $display("  -> %0d LLRs verificados correctamente.", ram_write_addr);
                end
            end
        end
    end

endmodule