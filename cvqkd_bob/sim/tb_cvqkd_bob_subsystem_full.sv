`timescale 1ns / 1ps

module tb_cvqkd_bob_subsystem_top();

    // =========================================================================
    // 1. PARÁMETROS GLOBALES
    // =========================================================================
    localparam int ADC_WIDTH        = 16;
    localparam int NUM_SAMPLES      = 13056; // Muestras de estimación
    localparam int N_BOB_DATA       = 26112; // Tamaño total de la trama de datos
    localparam int N_FIBER          = 27857; // Tamaño bruto ADC (Datos + Pilotos)
    localparam int BLOCKS_PER_FRAME = 3264;  // Bloques 8D en el MDR
    localparam int ROWS             = 46;    // Filas del Síndrome

    logic clk;
    logic rst_n;
    
    // --- Interfaces del DUT ---
    logic signed [ADC_WIDTH-1:0] p_in, q_in;
    logic                        valid_in;
    
    logic                        mask_valid, mask_bit;
    logic                        alice_stream_valid;
    logic [31:0]                 alice_stream_data;
    logic [7:0]                  trng_data;
    
    logic signed [31:0]          calib_VarA;
    logic                        skr_valid, skr_safe;
    logic signed [31:0]          T_final_out, sigma_sq_out, sigma_out, num_samples_out;
    logic                        irq, done_est, frame_valid_out;
    
    logic                        mdr_valid;
    logic [255:0]                mdr_m_out;
    logic                        syndrome_done;
    logic [383:0]                syndrome_out [0:45];

    // =========================================================================
    // 2. MEMORIAS PARA LEER LOS ARCHIVOS DE MATLAB
    // =========================================================================
    logic [31:0]  mem_adc      [0:N_FIBER-1];      // bob_raw_adc.txt
    logic         mem_mask     [0:N_BOB_DATA-1];   // mask_bit.txt
    logic [31:0]  mem_alice    [0:NUM_SAMPLES-1];  // alice_ram.txt
    logic [7:0]   mem_trng     [0:BLOCKS_PER_FRAME-1]; 
    logic [255:0] mem_m_exp    [0:BLOCKS_PER_FRAME-1];
    logic [383:0] mem_syn_exp  [0:ROWS-1];

    // =========================================================================
    // 3. GENERACIÓN DE RELOJ (100 MHz)
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // 4. INSTANCIACIÓN DEL SUBSISTEMA COMPLETO (DUT)
    // =========================================================================
    cvqkd_bob_subsystem_top #(
        .ADC_WIDTH(ADC_WIDTH),
        .NUM_SAMPLES(NUM_SAMPLES)
    ) dut (
        .* // Conecta automáticamente todas las señales con el mismo nombre
    );

    // =========================================================================
    // 5. EMULADOR DE CPU (AXI4-Lite ISR)
    // =========================================================================
    initial begin
        skr_valid  = 1'b0;
        skr_safe   = 1'b0;
        calib_VarA = 32'd262144000; // Valor ejemplo Q16.16 (4000.0)
        
        forever begin
            @(posedge clk);
            if (irq) begin
                $display("\n[CPU ARM] !INTERRUPCION RECIBIDA! Leyendo registros AXI...");
                $display("  -> T_final_out : %0d", T_final_out);
                $display("  -> sigma_out   : %0d", sigma_out);
                
                // Simulamos el tiempo de cómputo del SKR en el procesador en C
                $display("[CPU ARM] Calculando SKR y cota de Holevo...");
                repeat(50) @(posedge clk);
                
                $display("[CPU ARM] SKR Positivo. Autorizando trama (skr_safe = 1).");
                skr_safe  <= 1'b1;
                skr_valid <= 1'b1;
                @(posedge clk);
                skr_valid <= 1'b0; // Pulso de escritura finalizado
            end
        end
    end

    // =========================================================================
    // 6. ALINEACIÓN PRECISA DEL TRNG CON LA CÁMARA INTERNA
    // =========================================================================
    // Espiamos el cable interno 'valid_key' del DUT para avanzar el puntero del
    // TRNG exactamente cuando el Acumulador lee 4 dimensiones, garantizando 
    // que usamos los mismos números aleatorios que el Script de MATLAB.
    int trng_ptr = -1;
    int key_cnt  = 0;
    
    always_comb trng_data = mem_trng[trng_ptr];
    
    always_ff @(posedge clk) begin
        if (rst_n && dut.valid_key) begin
            if (key_cnt == 3) begin
                trng_ptr++;
                key_cnt = 0;
            end else begin
                key_cnt++;
            end
        end
    end

    // =========================================================================
    // 7. AUTO-CHECKERS: MDR Y SÍNDROME
    // =========================================================================
    int mdr_check_idx = 0;
    int mdr_err_count = 0;
    
    always_ff @(posedge clk) begin
        if (mdr_valid) begin
            for (int i = 0; i < 8; i++) begin
                logic signed [31:0] hw_m = mdr_m_out[(i*32) +: 32];
                logic signed [31:0] sw_m = mem_m_exp[mdr_check_idx][(i*32) +: 32];
                int err_diff = hw_m - sw_m;
                if (err_diff < 0) err_diff = -err_diff;
                
                if (err_diff > 0) begin
                    if (mdr_err_count < 10) $display("  [FAIL MDR] Bloque %0d | Dim %0d | Error %0d", mdr_check_idx, i+1, err_diff);
                    mdr_err_count++;
                end
            end
            mdr_check_idx++;
        end
        
        if (syndrome_done) begin
            int syn_err = 0;
            $display("\n[CHECKER] !Matriz de Sindrome Lista!");
            for (int i = 0; i < ROWS; i++) begin
                if (syndrome_out[i] !== mem_syn_exp[i]) syn_err++;
            end
            if (syn_err == 0) $display("  [ OK ] El Sindrome es PERFECTO y coincide con MATLAB.");
            else              $display("  [FAIL] %0d errores en las ecuaciones del Sindrome.", syn_err);
        end
    end

    // =========================================================================
    // 8. HILO PRINCIPAL: INYECCIÓN DE ESTÍMULOS (FIBRA Y RED CLÁSICA)
    // =========================================================================
    int alice_ptr = 0;
    
    initial begin
        rst_n              = 0;
        valid_in           = 0;
        p_in               = '0;
        q_in               = '0;
        mask_valid         = 0;
        mask_bit           = 0;
        alice_stream_valid = 0;
        alice_stream_data  = '0;

        $display("=========================================================================");
        $display("[TESTBENCH MAESTRO] Cargando el Gemelo Digital de MATLAB...");
        
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_raw_adc.txt", mem_adc);
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/mask_bit.txt", mem_mask);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/alice_ram.txt", mem_alice);
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_random_bits.txt", mem_trng);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_m_messages.txt", mem_m_exp);
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_syndrome.txt", mem_syn_exp);
        
        #100 rst_n = 1; #100;

        // ---------------------------------------------------------------------
        // FASE 1: LLEGA LA LUZ CUÁNTICA (El ADC dispara a 1 Gbaud)
        // ---------------------------------------------------------------------
        $display("[CANAL CUANTICO] Recibiendo %0d muestras del fotodiodo...", N_FIBER);
        for (int i = 0; i < N_FIBER; i++) begin
            @(posedge clk);
            valid_in <= 1'b1;
            p_in     <= mem_adc[i][15:0];   // Extraemos P
            q_in     <= mem_adc[i][31:16];  // Extraemos Q
        end
        @(posedge clk);
        // metemos 80 muestras de relleno para que el DUT procese la última trama
        for (int i = 0; i < 80; i++) begin
            @(posedge clk);
            valid_in <= 1'b1;
            p_in     <= 16'd0;
            q_in     <= 16'd0;
        end
        @(posedge clk);
        valid_in <= 1'b0;
        
        // ---------------------------------------------------------------------
        // FASE 2: ESPERA DEL PROTOCOLO DE RED
        // ---------------------------------------------------------------------
        $display("[RED] Esperando la llegada del paquete de Alice por Ethernet...");
        repeat(500) @(posedge clk);
        
        // ---------------------------------------------------------------------
        // FASE 3: LLEGA EL PAQUETE CLÁSICO (Máscara + Estimación)
        // ---------------------------------------------------------------------
        $display("[RED] Recibiendo Máscara y Datos de Estimacion (10%% de Lag inyectado)...");
        for (int i = 0; i < N_BOB_DATA; i++) begin
            @(posedge clk);
            mask_valid <= 1'b1;
            mask_bit   <= mem_mask[i];
            
            if (mem_mask[i] == 1'b1) begin
                alice_stream_valid <= 1'b1;
                alice_stream_data  <= mem_alice[alice_ptr];
                alice_ptr++;
            end else begin
                alice_stream_valid <= 1'b0;
            end
            
            // Simulamos jitter de red: a veces los paquetes clásicos se pausan
            if ($urandom_range(0, 100) < 10) begin
                @(posedge clk);
                mask_valid         <= 1'b0;
                alice_stream_valid <= 1'b0;
            end
        end
        
        @(posedge clk);
        mask_valid         <= 1'b0;
        alice_stream_valid <= 1'b0;

        // ---------------------------------------------------------------------
        // FASE 4: ESPERAR RESOLUCIÓN Y JUZGAR EL RESULTADO
        // ---------------------------------------------------------------------
        $display("\n[TESTBENCH] Datos inyectados. Esperando a que el Pipeline y la CPU terminen...");
        
        // Esperamos que el MDR procese todo (3264 bloques)
        wait(mdr_check_idx == BLOCKS_PER_FRAME);
        
        // Damos margen para que se imprima el Síndrome
        #500;
        
        $display("-------------------------------------------------------------------------");
        if (mdr_err_count == 0) $display("  [ EXITO ] MDR: Generacion perfecta del mensaje publico m.");
        else                    $display("  [ FALLO ] MDR: %0d errores detectados.", mdr_err_count);
        $display("=========================================================================");
        
        $finish;
    end

endmodule