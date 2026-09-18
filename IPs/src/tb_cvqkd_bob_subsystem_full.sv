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
    
    // --- Interfaces del DUT (AXI4-Stream) ---
    // 1. Esclavo P y Q
    logic [31:0]                 s_axis_pq_tdata;
    logic                        s_axis_pq_tvalid;
    logic                        s_axis_pq_tready;
    
    // 2. Recepción Alice y Señales Sueltas
    logic                        mask_valid, mask_bit;
    logic [31:0]                 s_axis_alice_tdata;
    logic                        s_axis_alice_tvalid;
    logic                        s_axis_alice_tready;
    
    logic [7:0]                  trng_data;
    
    // 3. AXI4-Lite Parámetros
    logic signed [31:0]          calib_VarA;
    logic signed [31:0]          T_final_out, T_sqrt_out, sigma_sq_out, sigma_out, num_samples_out;
    logic                        done_est;
    
    // 4. Maestros MDR y Síndrome
    logic [255:0]                m_axis_mdr_tdata;
    logic                        m_axis_mdr_tvalid;
    logic                        m_axis_mdr_tready;
    logic                        m_axis_mdr_tlast;

    logic [383:0]                m_axis_syndrome_tdata;
    logic                        m_axis_syndrome_tvalid;
    logic                        m_axis_syndrome_tready;
    logic                        m_axis_syndrome_tlast;

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
        .* 
    );

    // =========================================================================
    // 5. CONFIGURACIÓN DE LA CALIBRACIÓN (AXI4-Lite)
    // =========================================================================
    initial begin
        calib_VarA = 32'd40000; // Valor ejemplo Q16.16 (4000.0)
    end

    // =========================================================================
    // 6. ALINEACIÓN PRECISA DEL TRNG CON LA CÁMARA INTERNA
    // =========================================================================
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
    
    // Array para capturar el síndrome emitido por streaming
    logic [383:0] captured_syndrome [0:ROWS-1];
    int           syn_rows_captured = 0;
    int           syn_row_counter   = 0;
    
    logic         syndrome_check_flag    = 0;
    logic         syndrome_verified_flag = 0; 

    // Asignamos los tready a 1 porque el testbench siempre está listo para leer
    assign m_axis_mdr_tready      = 1'b1;
    assign m_axis_syndrome_tready = 1'b1;

    // Captura streaming de las filas del síndrome
    always_ff @(posedge clk) begin
        if (m_axis_syndrome_tvalid && m_axis_syndrome_tready) begin
            captured_syndrome[syn_row_counter] <= m_axis_syndrome_tdata;
            syn_rows_captured                  <= syn_rows_captured + 1;
            syn_row_counter                    <= syn_row_counter + 1;
        end
        
        if (m_axis_syndrome_tlast) begin
            syndrome_check_flag <= 1'b1;
        end
        
        // Verificación del Síndrome (Sin timing controls prohibidos)
        if (syndrome_check_flag) begin
            automatic int syn_err = 0; 
            syndrome_check_flag <= 1'b0; // Limpiamos la bandera
            
            $display("\n[CHECKER] !Matriz de Sindrome Lista!");
            if (syn_rows_captured != ROWS) begin
                $display("  [FAIL] Solo se recibieron %0d filas (esperadas %0d).", syn_rows_captured, ROWS);
                syn_err++;
            end
            for (int i = 0; i < ROWS; i++) begin
                if (captured_syndrome[i] !== mem_syn_exp[i]) syn_err++;
            end
            
            if (syn_err == 0) $display("  [ OK ] El Sindrome es PERFECTO y coincide con MATLAB.");
            else              $display("  [FAIL] %0d errores en las ecuaciones del Sindrome.", syn_err);
            
            syndrome_verified_flag <= 1'b1; // Avisamos de que hemos terminado de comprobar
        end
    end

    // Verificación del MDR
    always_ff @(posedge clk) begin
        if (m_axis_mdr_tvalid && m_axis_mdr_tready) begin
            for (int i = 0; i < 8; i++) begin
                automatic logic signed [31:0] hw_m = m_axis_mdr_tdata[(i*32) +: 32];
                automatic logic signed [31:0] sw_m = mem_m_exp[mdr_check_idx][(i*32) +: 32];
                automatic int err_diff = hw_m - sw_m;
                
                if (err_diff < 0) err_diff = -err_diff;
                
                if (err_diff > 0) begin
                    if (mdr_err_count < 10) $display("  [FAIL MDR] Bloque %0d | Dim %0d | Error %0d", mdr_check_idx, i+1, err_diff);
                    mdr_err_count++;
                end
            end
            mdr_check_idx++;
        end
    end

    // =========================================================================
    // 8. HILO PRINCIPAL: INYECCIÓN DE ESTÍMULOS (FIBRA Y RED CLÁSICA)
    // =========================================================================
    int alice_ptr = 0;
    
    initial begin
        rst_n               = 0;
        s_axis_pq_tvalid    = 0;
        s_axis_pq_tdata     = '0;
        mask_valid          = 0;
        mask_bit            = 0;
        s_axis_alice_tvalid = 0;
        s_axis_alice_tdata  = '0;

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
            s_axis_pq_tvalid <= 1'b1;
            // Concatenamos Q y P en un solo bus de 32 bits
            s_axis_pq_tdata  <= {mem_adc[i][31:16], mem_adc[i][15:0]}; 
        end
        @(posedge clk);
        // metemos 80 muestras de relleno para que el DUT procese la última trama
        for (int i = 0; i < 80; i++) begin
            @(posedge clk);
            s_axis_pq_tvalid <= 1'b1;
            s_axis_pq_tdata  <= 32'd0;
        end
        @(posedge clk);
        s_axis_pq_tvalid <= 1'b0;
        
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
                s_axis_alice_tvalid <= 1'b1;
                s_axis_alice_tdata  <= mem_alice[alice_ptr];
                alice_ptr++;
            end else begin
                s_axis_alice_tvalid <= 1'b0;
            end
            
            // Simulamos jitter de red: a veces los paquetes clásicos se pausan
            if ($urandom_range(0, 100) < 10) begin
                @(posedge clk);
                mask_valid          <= 1'b0;
                s_axis_alice_tvalid <= 1'b0;
            end
        end
        
        @(posedge clk);
        mask_valid          <= 1'b0;
        s_axis_alice_tvalid <= 1'b0;

        // ---------------------------------------------------------------------
        // FASE 4: ESPERAR RESOLUCIÓN Y JUZGAR EL RESULTADO
        // ---------------------------------------------------------------------
        $display("\n[TESTBENCH] Datos inyectados. Esperando a que el Pipeline termine...");
        
        wait(mdr_check_idx == BLOCKS_PER_FRAME);
        $display("[TESTBENCH] MDR completado. Esperando calculo del Sindrome LDPC...");
        
        // Esperamos explícitamente a que el checker verifique todo en lugar del #500 prohibido
        wait(syndrome_verified_flag == 1'b1);
        
        $display("-------------------------------------------------------------------------");
        if (mdr_err_count == 0) $display("  [ EXITO ] MDR: Generacion perfecta del mensaje publico.");
        else                    $display("  [ FALLO ] MDR: %0d errores detectados.", mdr_err_count);
        $display("=========================================================================");
        
        $finish;
    end

endmodule