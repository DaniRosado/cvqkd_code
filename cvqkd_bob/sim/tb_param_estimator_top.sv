`timescale 1ns / 1ps

module tb_param_estimator_top();

    // =========================================================================
    // PARÁMETROS Y SEÑALES
    // =========================================================================
    localparam TEST_SAMPLES = 26112/2; // 13056 Muestras de Sacrificio
    localparam NUM_BOB_RAM  = 52224;   // Tamaño total de la RAM de Bob
    
    logic clk, rst, start, done;
    
    // --- NUEVAS SEÑALES DE STREAMING ---
    logic        bob_stream_valid;
    logic [31:0] bob_stream_data;
    logic        alice_stream_valid;
    logic [31:0] alice_stream_data;
    
    // Calibración
    logic signed [31:0] calib_VarA;
    
    // Salidas Finales (Q16.16)
    logic signed [31:0] T_est, T_sqrt_est, sigma_sq_est, sigma_est;
    logic data_ready;

    // =========================================================================
    // ARRAYS DE MEMORIA (Lectura de archivos de MATLAB)
    // =========================================================================
    logic [15:0] mem_ptr    [0:TEST_SAMPLES-1];
    logic [31:0] mem_bob    [0:NUM_BOB_RAM-1]; 
    logic [31:0] mem_alice  [0:TEST_SAMPLES-1];
    logic [31:0] mem_expected [0:3];

    // =========================================================================
    // GENERACIÓN DE RELOJ (100 MHz)
    // =========================================================================
    always #5 clk = ~clk;

    // =========================================================================
    // INSTANCIACIÓN DEL DUT (Estimador de Parámetros)
    // =========================================================================
    param_estimator_top #(
        .NUM_SAMPLES(TEST_SAMPLES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .done(done),
        
        // Conectamos las nuevas tuberías de streaming
        .bob_stream_valid(bob_stream_valid),
        .bob_stream_data(bob_stream_data),
        .alice_stream_valid(alice_stream_valid),
        .alice_stream_data(alice_stream_data),
        
        .calib_VarA(calib_VarA),
        
        .T_final(T_est),
        .T_sqrt(T_sqrt_est),
        .sigma_sq(sigma_sq_est),
        .sigma(sigma_est),
        .data_ready(data_ready)
    );

    // =========================================================================
    // PROCEDIMIENTO DE TEST
    // =========================================================================
    initial begin
        // 1. Inicialización a cero
        clk = 0;
        rst = 1;
        start = 0;
        bob_stream_valid   = 0;
        alice_stream_valid = 0;
        bob_stream_data    = 0;
        alice_stream_data  = 0;
        
        // Varianza de calibración exacta que espera MATLAB
        calib_VarA = 32'd40000; 

        // 2. Cargar Archivos (Ajusta tus rutas absolutas si es necesario)
        $display("-------------------------------------------------------------------------");
        $display("[TB] Cargando archivos generados por MATLAB...");
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/ptr_ram.txt", mem_ptr);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_ram.txt", mem_bob);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/alice_ram.txt", mem_alice);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_llr_math.txt", mem_expected);
        $display("[TB] Archivos cargados con exito.");

        #20 rst = 0;
        #20;

        // 3. Inicio del bloque
        $display("[TB] Mandando pulso de START al estimador...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        //start = 0;
        @(posedge clk);

        // 4. INYECCIÓN DE STREAMING (Emulando al Router)
        $display("[TB] Inyectando las 13.056 muestras en Streaming (1 por ciclo de reloj)...");
        
        for (int i = 0; i < TEST_SAMPLES; i++) begin
            
            // a) Miramos la máscara/puntero para saber qué dato coger de Bob
            int ptr_sacrificio = mem_ptr[i];
            
            // b) Preparamos los datos en los cables
            bob_stream_data   = mem_bob[ptr_sacrificio];
            alice_stream_data = mem_alice[i];
            
            // c) Levantamos las banderas de "Dato Válido"
            bob_stream_valid   = 1;
            alice_stream_valid = 1;
            
            // d) Esperamos 1 flanco de reloj (El hardware se traga el dato)
            @(posedge clk);
            
            // ===============================================================
            // (OPCIONAL): Prueba de Estrés de la FIFO
            // Si quieres ver lo robusto que es tu diseño, puedes descomentar 
            // esto para inyectar datos con pausas aleatorias simulando una red lenta.
            // ===============================================================

            if ($urandom_range(0, 10) > 8) begin
                bob_stream_valid   = 0;
                alice_stream_valid = 0;
                @(posedge clk);
                @(posedge clk);
            end
            
        end
        
        // 5. Apagamos el grifo de datos
        bob_stream_valid   = 0;
        alice_stream_valid = 0;
        $display("[TB] Inyeccion terminada. Esperando a que termine el calculo matematico...");

        // 6. Esperar a que la unidad de división termine (done = 1)
        wait(done == 1'b1);
        @(posedge clk);
        
        // 7. COMPROBACIÓN DE ERRORES CONTRA MATLAB
        begin
            integer err [4];
            integer i;
            
            err[0] = T_est        - mem_expected[0];
            err[1] = T_sqrt_est   - mem_expected[1];
            err[2] = sigma_sq_est - mem_expected[2];
            err[3] = sigma_est    - mem_expected[3];

            // Valor absoluto de los errores
            for(i=0; i<4; i++) if(err[i] < 0) err[i] = -err[i];

            $display("-------------------------------------------------------------------------");
            $display("    PARAMETRO     | FPGA (Q16.16) | MATLAB (Ideal) | ERROR (Bits) ");
            $display("------------------+---------------+----------------+------------------");
            $display(" Ganancia T_est   |  %12d |   %12d |   %8d", T_est,        mem_expected[0], err[0]);
            $display(" Raiz Sqrt(T)     |  %12d |   %12d |   %8d", T_sqrt_est,   mem_expected[1], err[1]);
            $display(" Varianza Sigma^2 |  %12d |   %12d |   %8d", sigma_sq_est, mem_expected[2], err[2]);
            $display(" Desviacion Sigma |  %12d |   %12d |   %8d", sigma_est,    mem_expected[3], err[3]);
            $display("-------------------------------------------------------------------------");

            if (err[0]<=5 && err[1]<=5 && err[2]<=5 && err[3]<=5) begin
                $display("  [ OK ]  ¡EXITO! El hardware emula a MATLAB con precision perfecta.");
            end else begin
                $display("  [ X ]   ¡FALLO! Error detectado en la cadena matematica.");
            end
            $display("=========================================================================");
        end
        
        $finish;
    end

endmodule