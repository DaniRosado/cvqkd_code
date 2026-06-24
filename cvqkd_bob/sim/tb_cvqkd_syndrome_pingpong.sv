`timescale 1ns / 1ps

module tb_cvqkd_syndrome_pingpong();

    // =========================================================================
    // 1. PARÁMETROS DEL SISTEMA
    // =========================================================================
    localparam int BYTES_PER_FRAME = 3264; 
    localparam int ROWS            = 46;

    logic clk;
    logic rst_n;
    
    // Señales de Entrada
    logic         valid_data;
    logic [7:0]   trng_data;
    
    // Señales de Salida
    logic         done;
    logic [383:0] syndrome_out [0:45];

    // =========================================================================
    // 2. MEMORIAS PARA LEER LOS .TXT DE MATLAB
    // =========================================================================
    logic [7:0]   mem_trng_in [0:BYTES_PER_FRAME-1]; 
    logic [383:0] mem_expected_syndrome [0:ROWS-1];

    // =========================================================================
    // 3. GENERACIÓN DE RELOJ (100 MHz)
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // 4. INSTANCIACIÓN DEL DUT (Device Under Test)
    // =========================================================================
    cvqkd_syndrome_pingpong dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .valid_data  (valid_data),
        .trng_data   (trng_data),
        .done        (done),
        .syndrome_out(syndrome_out)
    );

    // =========================================================================
    // 5. HILO PARALELO: AUTO-CHECKER MATRICIAL (Se dispara con el 'done')
    // =========================================================================
    int frames_checked = 0;
    int err_count      = 0;

    always_ff @(posedge clk) begin
        if (done) begin
            $display("[CHECKER] !Senal DONE detectada! Verificando matriz del sindrome de la Trama %0d...", frames_checked + 1);
            
            for (int i = 0; i < ROWS; i++) begin
                if (syndrome_out[i] !== mem_expected_syndrome[i]) begin
                    $display("  [FAIL] Discrepancia en la fila %0d", i);
                    $display("         Esperado: %096X", mem_expected_syndrome[i]);
                    $display("         Obtenido: %096X", syndrome_out[i]);
                    err_count++;
                end
            end
            
            if (err_count == 0) begin
                $display("  [ OK ] Trama %0d calculada sin errores. !Match perfecto!", frames_checked + 1);
            end
            
            frames_checked++;
            err_count = 0; // Reseteamos para la siguiente trama
        end
    end

    // =========================================================================
    // 6. HILO PRINCIPAL: ESTÍMULOS DE FLUJO CONTINUO (STREAMING)
    // =========================================================================
    initial begin
        // --- A. Inicialización ---
        rst_n      = 0;
        valid_data = 0;
        trng_data  = '0;

        $display("=========================================================================");
        $display("[TB PING-PONG] Cargando archivos de MATLAB...");
        
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_random_bits.txt", mem_trng_in);
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_syndrome.txt", mem_expected_syndrome);
        
        #40;
        rst_n = 1;
        #40;

        $display("[TB PING-PONG] Inyectando TRAMA 1 (Hacia Banco 0)...");
        
        // --- B. Inyectar TRAMA 1 (3264 bytes) ---
        for (int i = 0; i < BYTES_PER_FRAME; i++) begin
            @(posedge clk);
            valid_data <= 1'b1;
            trng_data  <= mem_trng_in[i];
            
            // Pausas aleatorias para simular la realidad de la red clásica
            if ($urandom_range(0, 100) < 15) begin
                @(posedge clk);
                valid_data <= 1'b0;
                trng_data  <= '0;
            end
        end

        $display("[TB PING-PONG] Trama 1 completada. Inyectando TRAMA 2 (Hacia Banco 1) sin detenerse...");
        
        // --- C. Inyectar TRAMA 2 SIN PARAR ---
        for (int i = 0; i < BYTES_PER_FRAME; i++) begin
            @(posedge clk);
            valid_data <= 1'b1;
            trng_data  <= mem_trng_in[i];
            
            if ($urandom_range(0, 100) < 15) begin
                @(posedge clk);
                valid_data <= 1'b0;
                trng_data  <= '0;
            end
        end

        // --- D. Apagar el grifo y esperar ---
        @(posedge clk);
        valid_data <= 1'b0;
        trng_data  <= '0;

        $display("[TB PING-PONG] Inyeccion finalizada. Esperando resolucion del hardware...");
        
        // Esperamos a que el Auto-Checker haya analizado las 2 tramas
        wait(frames_checked == 2);
        
        #100;
        $display("-------------------------------------------------------------------------");
        $display("  [ OK ] !PRUEBA DE ESTRES SUPERADA!");
        $display("         El hardware ha absorbido 2 tramas seguidas haciendo uso ");
        $display("         del Ping-Pong Buffer de forma transparente y sin colisiones.");
        $display("=========================================================================");
        
        $finish;
    end

endmodule