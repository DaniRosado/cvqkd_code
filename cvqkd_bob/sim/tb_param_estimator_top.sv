`timescale 1ns / 1ps

module tb_param_estimator_top();

    // =========================================================================
    // PARÁMETROS Y SEÑALES
    // =========================================================================
    localparam TEST_SAMPLES = 26112;
    localparam NUM_BOB_RAM  = 52224; // Tamaño total de la RAM de Bob
    
    logic clk, rst, start, ping_pong_bit, done;
    
    // Buses de Memoria
    logic [14:0] ptr_addr;   logic [15:0] ptr_data;
    logic [16:0] bob_addr;   logic [31:0] bob_data;
    logic [14:0] alice_addr; logic [31:0] alice_data;
    
    // Calibración
    logic signed [31:0] calib_VarA;
    
    // Salidas Finales (Q16.16)
    logic signed [31:0] T_est, T_sqrt_est, sigma_sq_est, sigma_est;

    // Control de flujo On-the-fly
    logic [15:0] alice_items_avail;
    logic [15:0] bob_items_avail;

    // =========================================================================
    // ARRAYS DE MEMORIA (Emulación de BRAMs)
    // =========================================================================
    logic [15:0] mem_ptr   [0:TEST_SAMPLES-1];
    logic [31:0] mem_bob   [0:NUM_BOB_RAM-1]; 
    logic [31:0] mem_alice [0:TEST_SAMPLES-1];
    logic [31:0] mem_expected [0:3]; // T, sqrt(T), sigma_sq, sigma

    // =========================================================================
    // INSTANCIA DEL TOP-LEVEL
    // =========================================================================
    param_estimator_top #(.NUM_SAMPLES(TEST_SAMPLES)) dut (
        .clk(clk), .rst(rst),
        .start(start), .ping_pong_bit(ping_pong_bit), .done(done),
        
        .ptr_addr(ptr_addr), .ptr_data(ptr_data),
        .bob_addr(bob_addr), .bob_data(bob_data),
        .alice_addr(alice_addr), .alice_data(alice_data),
        
        .alice_items_avail(alice_items_avail),
        .bob_items_avail(bob_items_avail),
        
        .calib_VarA(calib_VarA),
        
        .T_estimated(T_est),
        .T_sqrt_estimated(T_sqrt_est),
        .sigma_sq_estimated(sigma_sq_est),
        .sigma_estimated(sigma_est)
    );

    // =========================================================================
    // GENERACIÓN DE RELOJ Y LOGICA DE RAM
    // =========================================================================
    initial begin
        clk = 0; forever #5 clk = ~clk;
    end

    // Emulación de latencia de 1 ciclo (típica de BRAM)
    always_ff @(posedge clk) begin
        ptr_data   <= mem_ptr[ptr_addr];
        bob_data   <= mem_bob[bob_addr[15:0]]; // Usamos solo 16 bits para indexar
        alice_data <= mem_alice[alice_addr];
    end

    // =========================================================================
    // EMULACIÓN DE LLEGADA DE DATOS ON-THE-FLY
    // =========================================================================
    initial begin
        alice_items_avail = 0;
        bob_items_avail = 0;
        wait(rst == 0);
        
        fork
            // Emulamos recepción de red (Alice)
            begin
                while (alice_items_avail < TEST_SAMPLES) begin
                    @(posedge clk);
                    if ($random % 4 != 0) alice_items_avail++; // A veces se pausa la red
                end
            end
            // Emulamos el generador de Bob
            begin
                while (bob_items_avail < TEST_SAMPLES) begin
                    @(posedge clk);
                    if ($random % 2 != 0) bob_items_avail++; // Generador más lento
                end
            end
        join
    end

    // =========================================================================
    // PROCEDIMIENTO DE TEST
    // =========================================================================
    initial begin
        // 1. Carga de datos generados por MATLAB
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/ptr_ram.txt", mem_ptr);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/bob_ram.txt", mem_bob);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/alice_ram.txt", mem_alice);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/expected_llr_math.txt", mem_expected);

        // 2. Configuración Inicial
        rst = 1; start = 0; ping_pong_bit = 0;
        calib_VarA = 32'd40000; // 4.0 SNU * 10000
        
        #50 rst = 0;
        
        $display("\n=======================================================");
        $display("[INFO] Iniciando Estimador de Parametros (Escala Real)");
        $display("[INFO] Procesando %0d muestras...", TEST_SAMPLES);
        
        // 3. Disparo del sistema
        @(posedge clk) start = 1'b1;
        @(posedge clk) start = 1'b0;
        
        // 4. Espera del resultado
        // Tardará ~26.000 ciclos en procesar + ~60 ciclos de pipeline matemático
        wait(done == 1'b1);
        
        $display("[INFO] Estimacion completada.");

        // 5. Verificación de Resultados
        comparar_resultados();
        
        #100 $finish;
    end

    // =========================================================================
    // TAREA DE COMPARACIÓN
    // =========================================================================
    task comparar_resultados();
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

        if (err[0] < 5 && err[1] < 5 && err[2] < 5 && err[3] < 5) begin
            $display("  [ OK ] ¡SISTEMA INTEGRADO VERIFICADO CON EXITO! ");
        end else begin
            $display("  [ X ]  ¡FALLO DE TOLERANCIA DETECTADO! ");
        end
        $display("=======================================================\n");
    endtask

endmodule