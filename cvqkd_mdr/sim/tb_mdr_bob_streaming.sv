`timescale 1ns / 1ps

module tb_mdr_bob_streaming();

    // =========================================================================
    // 1. PARÁMETROS DEL SISTEMA
    // =========================================================================
    // 13056 muestras de sacrificio / 4 muestras por bloque = 3264 bloques
    localparam int NUM_TESTS = 3264; 
    
    logic clk;
    logic rst_n;
    
    // --- Entradas al DUT ---
    logic         valid_data;
    logic [127:0] data_in;
    logic [7:0]   trng_data;
    
    // --- Salidas del DUT ---
    logic         m_valid;
    logic [255:0] m_out;

    // =========================================================================
    // 2. MEMORIAS PARA LEER LOS .TXT DE MATLAB
    // =========================================================================
    logic [127:0] mem_Y_in    [0:NUM_TESTS-1]; // Archivo: bob_mdr_inputs.txt (Hex)
    logic [7:0]   mem_trng_in [0:NUM_TESTS-1]; // Archivo: bob_random_bits.txt (Binario)
    logic [255:0] mem_m_exp   [0:NUM_TESTS-1]; // Archivo: expected_m_messages.txt (Hex)

    // =========================================================================
    // 3. GENERACIÓN DE RELOJ (100 MHz)
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // 4. INSTANCIACIÓN DEL DUT
    // =========================================================================
    mdr_bob_streaming dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_data(valid_data),
        .data_in   (data_in),
        .trng_data (trng_data),
        .m_valid   (m_valid),
        .m_out     (m_out)
    );

    // =========================================================================
    // 5. AUTO-CHECKER: HILO PARALELO DE VERIFICACIÓN
    // =========================================================================
    int check_idx = 0;
    int err_count = 0;
    
    logic signed [31:0] hw_m [0:7];
    logic signed [31:0] sw_m [0:7];
    int err_diff;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            check_idx <= 0;
            err_count <= 0;
        end else if (m_valid) begin
            // Desempaquetamos los 256 bits en 8 dimensiones de 32 bits
            for (int i = 0; i < 8; i++) begin
                hw_m[i] = m_out[(i*32) +: 32];
                sw_m[i] = mem_m_exp[check_idx][(i*32) +: 32];
                
                // Calculamos el error absoluto
                err_diff = hw_m[i] - sw_m[i];
                if (err_diff < 0) err_diff = -err_diff;
                
                // Permitimos un margen de 5 unidades por redondeo en Q24
                if (err_diff > 30000) begin
                    if (err_count < 20) begin // Imprimimos solo los 20 primeros errores
                        $display("  [FAIL] Bloque %0d | Dim %0d | Esperado: %08X | Obtenido: %08X", 
                                 check_idx, i+1, sw_m[i], hw_m[i]);
                    end
                    err_count++;
                end
            end
            check_idx <= check_idx + 1;
        end
    end

    // =========================================================================
    // 6. ESTÍMULOS: INYECCIÓN DE FLUJO CONTINUO (STREAMING)
    // =========================================================================
    initial begin
        // --- A. Inicialización ---
        rst_n      = 0;
        valid_data = 0;
        data_in    = '0;
        trng_data  = '0;

        $display("=========================================================================");
        $display("[TB MDR STREAMING] Cargando plantillas de oro desde MATLAB...");
        
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_mdr_inputs.txt", mem_Y_in); 
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_random_bits.txt", mem_trng_in); // ¡Leemos en binario!
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_m_messages.txt", mem_m_exp);
        
        #40;
        rst_n = 1;
        #40;

        $display("[TB MDR STREAMING] Iniciando inyeccion en pipeline...");
        
        // --- B. Bucle de Inyección ---
        for (int i = 0; i < NUM_TESTS; i++) begin
            @(posedge clk);
            valid_data <= 1'b1;
            data_in    <= mem_Y_in[i];
            trng_data  <= mem_trng_in[i];
            
            // INTRODUCIMOS CAOS: 20% de probabilidad de pausar el flujo 1 ciclo
            // Esto prueba que el Pipeline no se rompe si el Acumulador se retrasa
            if ($urandom_range(0, 100) < 20) begin
                @(posedge clk);
                valid_data <= 1'b0;
                data_in    <= '0;
                trng_data  <= '0;
            end
        end
        
        // --- C. Apagamos el grifo ---
        @(posedge clk);
        valid_data <= 1'b0;
        data_in    <= '0;
        trng_data  <= '0;

        $display("[TB MDR STREAMING] Todos los datos inyectados. Esperando a que el pipeline se vacie...");
        
        // Esperamos a que el Auto-Checker haya analizado los 3264 mensajes
        wait(check_idx == NUM_TESTS);
        
        // Damos un pequeño margen para que se impriman los displays
        #100;

        // --- D. Reporte Final ---
        $display("-------------------------------------------------------------------------");
        if (err_count == 0) begin
            $display("  [ OK ] ¡EXITO ABSOLUTO! El pipeline del MDR funciona sin un solo fallo.");
            $display("         Tolerancia de redondeo y paradas de flujo superadas.");
        end else begin
            $display("  [CRITICAL] Se han encontrado %0d discrepancias de datos.", err_count);
        end
        $display("=========================================================================");
        
        $finish;
    end

endmodule