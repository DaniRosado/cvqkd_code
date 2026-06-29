`timescale 1ns / 1ps

module tb_ldpc_decoder_top();

    // ==========================================
    // 1. PARÁMETROS Y SEÑALES
    // ==========================================
    localparam int Z = 384;
    localparam int W = 8;
    localparam int BUS_WIDTH = Z * W;

    logic clk;
    logic rst_n;
    
    logic start_decoding;
    logic decoding_done;
    logic decoding_success;
    
    // Interfaz del Loader de LLRs (Alice)
    logic                 load_mode;
    logic                 load_write_en;
    logic [6:0]           load_write_addr;
    logic [BUS_WIDTH-1:0] load_write_data;

    // NUEVO: Interfaz del Loader de Síndrome (Bob)
    logic                 syn_load_en;
    logic [5:0]           syn_load_addr;
    logic [Z-1:0]         syn_load_data;

    // Arrays temporales en el TB para leer los archivos de MATLAB
    logic [BUS_WIDTH-1:0] u_bits_mem [0:67];
    logic [Z-1:0]         expected_syndrome_mem [0:45];

    // ==========================================
    // 2. INSTANCIA DEL TOP-LEVEL (DUT)
    // ==========================================
    ldpc_decoder_top #(
        .Z(Z), .W(W), .PIPELINE_DEPTH(3)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_decoding  (start_decoding),
        .decoding_done   (decoding_done),
        .decoding_success(decoding_success),
        
        .load_mode       (load_mode),
        .load_write_en   (load_write_en),
        .load_write_addr (load_write_addr),
        .load_write_data (load_write_data),
        
        // Conexión de los nuevos puertos del síndrome
        .syn_load_en     (syn_load_en),
        .syn_load_addr   (syn_load_addr),
        .syn_load_data   (syn_load_data)
    );

    // ==========================================
    // 3. GENERADOR DE RELOJ (100 MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // 4. ESTÍMULOS DE SIMULACIÓN
    // ==========================================
    initial begin
        // Estado inicial de las señales
        rst_n           = 0;
        start_decoding  = 0;
        
        load_mode       = 0;
        load_write_en   = 0;
        load_write_addr = 0;
        load_write_data = 0;
        
        syn_load_en     = 0;
        syn_load_addr   = 0;
        syn_load_data   = 0;

        $display("==================================================");
        $display("[TB] INICIANDO MASTER TESTBENCH: LDPC DECODER");
        $display("==================================================");

        // A. Cargar datos desde los archivos exportados de MATLAB
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/u_bits.txt", u_bits_mem);
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_syndrome.txt", expected_syndrome_mem);
        
        $display("[TB] Archivos 'u_bits.txt' y 'expected_syndrome.txt' cargados.");

        // Soltar el reset
        #20 rst_n = 1;
        #15;

        // B. Fase de Carga del Síndrome de Bob
        $display("[TB] %0t: Escribiendo Síndrome de Bob en memoria estatica...", $time);
        @(posedge clk);
        for (int i = 0; i < 46; i++) begin
            syn_load_en   <= 1'b1;
            syn_load_addr <= i;
            syn_load_data <= expected_syndrome_mem[i];
            @(posedge clk);
        end
        syn_load_en <= 1'b0;

        // C. Fase de Carga de las métricas (Inyección en la L_BRAM)
        $display("[TB] %0t: Inyectando metricas cuanticas (LLRs) en L_BRAM...", $time);
        @(posedge clk);
        load_mode = 1'b1;

        for (int i = 0; i < 68; i++) begin
            load_write_en   <= 1'b1;
            load_write_addr <= i;
            load_write_data <= u_bits_mem[i];
            @(posedge clk);
        end

        load_write_en <= 1'b0;
        
        @(posedge clk);
        load_mode <= 1'b0; // Devolvemos el control a la FSM interna

        $display("[TB] %0t: Todas las inyecciones completadas. FSM lista para operar.", $time);

        // D. Arrancar la Decodificación
        $display("[TB] %0t: Disparando start_decoding...", $time);
        @(posedge clk);
        start_decoding <= 1'b1;
        @(posedge clk);
        start_decoding <= 1'b0;

        // E. Esperar a que la FSM termine
        wait(decoding_done == 1'b1);

        // F. Veredicto Final
        $display("==================================================");
        $display("[TB] %0t: ¡DECODIFICACIÓN TERMINADA!", $time);
        
        if (decoding_success) begin
            $display("[TB] RESULTADO: *** ÉXITO ***");
            $display("[TB] El síndrome coincide perfectamente.");
            $display("[TB] ¡Alice y Bob comparten la misma clave cuántica!");
        end else begin
            $display("[TB] RESULTADO: *** FALLO ***");
            $display("[TB] Se alcanzó el límite de iteraciones sin converger.");
        end
        $display("==================================================");

        $finish;
    end

    // ==========================================
    // 5. WATCHDOG (Timeout de Seguridad)
    // ==========================================
    initial begin
        #25000000;
        $display("[TB] ERROR CRÍTICO: Timeout alcanzado. La FSM no responde.");
        $finish;
    end
    
    // =====================================================================
    // MONITOR DE SÍNDROME (Diagnóstico de convergencia)
    // =====================================================================
    logic [7:0] syn_iter_count = 0;
    logic [5:0] syn_fail_rows;

    always_ff @(posedge clk) begin
        if (dut.u_FSM.iter_start) begin
            syn_iter_count <= syn_iter_count + 1;
            syn_fail_rows <= 0;
        end
        if (dut.u_SYNDROME.row_done) begin
            if (!dut.u_SYNDROME.row_ok) begin
                syn_fail_rows <= syn_fail_rows + 1;
                if (syn_iter_count < 3) begin
                    $display("[SYN] Iter %0d | Fila %0d FALLO | Errores: %0d/384",
                             syn_iter_count, dut.u_FSM.row_idx,
                             $countones(dut.u_SYNDROME.row_errors));
                end
                // Debug: mostrar info detallada en iter 6 y 7
                if (syn_iter_count >= 6 && syn_iter_count <= 7 && dut.u_FSM.row_idx == 0) begin
                    $display("[DEBUG] Iter %0d, Fila 0: syn_accum[0:7]=%b, target[0:7]=%b",
                             syn_iter_count,
                             dut.u_DATAPATH.syn_accum[7:0],
                             expected_syndrome_mem[0][7:0]);
                end
            end
        end
        if (dut.u_FSM.state == 4) begin
            $display("[SYN] Iter %0d terminada | Filas fallidas: %0d/46 | is_converged=%b",
                     syn_iter_count, syn_fail_rows, dut.u_SYNDROME.is_converged);
        end
    end

endmodule