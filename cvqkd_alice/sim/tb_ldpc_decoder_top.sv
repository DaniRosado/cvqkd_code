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
    
    // Interfaz del Loader
    logic                 load_mode;
    logic                 load_write_en;
    logic [6:0]           load_write_addr;
    logic [BUS_WIDTH-1:0] load_write_data;

    // Array temporal en el TB para leer el archivo de MATLAB
    logic [BUS_WIDTH-1:0] u_bits_mem [0:67];

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
        .load_write_data (load_write_data)
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

        $display("==================================================");
        $display("[TB] INICIANDO MASTER TESTBENCH: LDPC DECODER");
        $display("==================================================");

        // A. Cargar datos desde el archivo exportado de MATLAB
        // Asegúrate de que u_bits.txt y expected_syndrome.txt están en la misma carpeta que el proyecto de simulación
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/u_bits.txt", u_bits_mem);
        $display("[TB] Archivo 'u_bits.txt' cargado en memoria temporal.");

        // Soltar el reset
        #20 rst_n = 1;
        #15;

        // B. Fase de Carga (Inyección en la L_BRAM)
        $display("[TB] %0t: Tomando el control del bus de memoria (load_mode = 1)...", $time);
        @(posedge clk);
        load_mode = 1'b1;

        for (int i = 0; i < 68; i++) begin
            @(posedge clk);
            load_write_en   <= 1'b1;
            load_write_addr <= i;
            load_write_data <= u_bits_mem[i];
        end

        @(posedge clk);
        load_write_en <= 1'b0;
        
        @(posedge clk);
        load_mode <= 1'b0; // Devolvemos el control a la FSM interna
        $display("[TB] %0t: Inyección completada. FSM lista para operar.", $time);
        
        // C. Arrancar la Decodificación
        $display("[TB] %0t: Disparando start_decoding...", $time);
        @(posedge clk);
        start_decoding <= 1'b1;
        @(posedge clk);
        start_decoding <= 1'b0;

        // D. Esperar a que la FSM termine
        // (Esto puede tardar miles de ciclos de reloj dependiendo de las iteraciones)
        wait(decoding_done == 1'b1);

        // E. Veredicto Final
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
    // Si la FSM se queda atascada en un bucle infinito, cortamos la simulación
    initial begin
        #25000000; // Ajusta este tiempo si tu simulación es muy larga
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
                // Solo imprimimos las primeras iteraciones para no saturar
                if (syn_iter_count < 3) begin
                    $display("[SYN] Iter %0d | Fila %0d FALLO | Errores: %0d/384",
                             syn_iter_count, dut.u_FSM.row_idx,
                             $countones(dut.u_SYNDROME.row_errors));
                end
            end
        end
        if (dut.u_FSM.state == 4) begin // CHECK_SYNDROME state (enum pos 4)
            $display("[SYN] Iter %0d terminada | Filas fallidas: %0d/46 | is_converged=%b",
                     syn_iter_count, syn_fail_rows, dut.u_SYNDROME.is_converged);
        end
    end

    /*
    // =====================================================================
    // AUTO-CHECKER GLOBAL (Verificación de 2 iteraciones, 632 edges)
    // =====================================================================
    localparam int TOTAL_EDGES = 632;

    logic [BUS_WIDTH-1:0] expected_l_write_mem [0:TOTAL_EDGES-1];
    int current_write_idx = 0;
    int errors_total = 0;

    initial begin
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_L_write_all.txt", expected_l_write_mem);
    end

    // Espiamos DIRECTAMENTE los puertos de salida de la FSM y el Datapath
    always_ff @(posedge clk) begin
        if (dut.u_FSM.p_write_en) begin
            $display("[CHECKER %0t] Edge %0d/%0d | Iter %0d | Fila %0d | Col %0d",
                     $time, current_write_idx, TOTAL_EDGES,
                     current_write_idx / 316, dut.u_FSM.row_idx, dut.u_FSM.p_write_addr);

            // Comparamos el bus gigante de 3072 bits del Datapath
            if (dut.u_DATAPATH.p_write_data_flat !== expected_l_write_mem[current_write_idx]) begin
                errors_total++;
                $display("   [!!!] DISCREPANCIA en edge %0d (Fila %0d, Col %0d)",
                         current_write_idx, dut.u_FSM.row_idx, dut.u_FSM.p_write_addr);

                // Barrido cable a cable para localizar la posición Z exacta
                for (int z = 0; z < 384; z++) begin
                    logic [7:0] hw_val = dut.u_DATAPATH.p_write_data_flat[z*8 +: 8];
                    logic [7:0] ex_val = expected_l_write_mem[current_write_idx][z*8 +: 8];

                    if (hw_val !== ex_val) begin
                        $display("      Z=%0d | HW=%h, EXP=%h", z, hw_val, ex_val);
                    end
                end
            end else begin
                $display("   [OK]");
            end

            current_write_idx++;

            // Cuando hemos verificado todos los edges (2 iteraciones)
            if (current_write_idx == TOTAL_EDGES) begin
                $display("==================================================");
                if (errors_total == 0) begin
                    $display("[CHECKER] EXITO: 2 iteraciones (%0d edges) perfectas.", TOTAL_EDGES);
                end else begin
                    $display("[CHECKER] FALLO: %0d/%0d edges con discrepancias.", errors_total, TOTAL_EDGES);
                end
                $display("==================================================");
                $finish;
            end
        end
    end
    */
endmodule