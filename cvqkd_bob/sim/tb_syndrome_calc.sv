`timescale 1ns / 1ps

module tb_syndrome_calc_bg1();

    // =========================================================================
    // 1. PARÁMETROS DEL SISTEMA LDPC (BG1)
    // =========================================================================
    localparam int Z = 384;
    localparam int COLS = 68; // Columnas del Base Graph (Datos + Paridad)
    localparam int ROWS = 46; // Filas del Base Graph (Check Nodes)

    logic clk;
    logic rst_n;
    logic start;

    // Interfaz de memoria y DUT
    logic [6:0]   u_addr;
    logic [383:0] u_data_in;
    logic         done;
    logic [383:0] syndrome_out [0:45];

    // =========================================================================
    // 2. MEMORIAS DEL TESTBENCH (Plantillas de Oro)
    // =========================================================================
    // Memoria que emula la RAM de Bob/Alice (68 palabras de 384 bits)
    logic [Z-1:0] mem_u_bits [0:COLS-1];
    
    // Memoria con el síndrome teórico calculado por MATLAB (46 palabras de 384 bits)
    logic [Z-1:0] mem_expected_syndrome [0:ROWS-1];

    // =========================================================================
    // 3. GENERACIÓN DE RELOJ (100 MHz)
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // 4. EMULADOR DE BRAM (Latencia de 1 ciclo)
    // =========================================================================
    // El módulo pide una dirección en u_addr, y la RAM entrega el dato en el siguiente flanco
    always_ff @(posedge clk) begin
        if (u_addr < COLS) begin
            u_data_in <= mem_u_bits[u_addr];
        end else begin
            u_data_in <= '0;
        end
    end

    // =========================================================================
    // 5. INSTANCIACIÓN DEL DUT (Device Under Test)
    // =========================================================================
    syndrome_calc_bg1 dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .u_addr(u_addr),
        .u_data_in(u_data_in),
        .done(done),
        .syndrome_out(syndrome_out)
    );

    // =========================================================================
    // 6. PROCEDIMIENTO PRINCIPAL DE TEST
    // =========================================================================
    int err_count = 0;

    initial begin
        // --- A. Inicialización ---
        rst_n = 0;
        start = 0;

        $display("=========================================================================");
        $display("[TB LDPC] Iniciando validación del cálculo de Síndrome (H x C)...");
        
        // --- B. Cargar archivos de MATLAB ---
        // IMPORTANTE: Asegúrate de que el nombre coincida con los que exportas en tu script
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/block_bits.txt", mem_u_bits); 
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_syndrome.txt", mem_expected_syndrome);
        
        #40;
        rst_n = 1;
        #40;

        // --- C. Disparo de la Máquina de Estados (PULSO ESTRICTO DE 1 CICLO) ---
        $display("[TB LDPC] Mandando pulso START al hardware...");
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0; // Apagamos inmediatamente para evitar el borrado al terminar

        // --- D. Esperar a que termine ---
        $display("[TB LDPC] Calculando... (Esperando señal DONE)");
        wait(done == 1'b1);
        
        // Damos un ciclo de gracia para que se estabilicen las señales de salida
        @(posedge clk);

        // --- E. AUTO-CHECKER MATRICIAL ---
        $display("[TB LDPC] Cálculo terminado. Comprobando las 46 filas...");
        $display("-------------------------------------------------------------------------");
        
        for (int i = 0; i < ROWS; i++) begin
            if (syndrome_out[i] !== mem_expected_syndrome[i]) begin
                $display("  [FAIL] Discrepancia en la fila %0d", i);
                $display("         Esperado: %096X", mem_expected_syndrome[i]);
                $display("         Obtenido: %096X", syndrome_out[i]);
                err_count++;
            end
        end

        // --- F. Reporte Final ---
        $display("-------------------------------------------------------------------------");
        if (err_count == 0) begin
            $display("  [ OK ] ¡EXITO ABSOLUTO! El hardware replica exactamente la matriz de MATLAB.");
        end else begin
            $display("  [CRITICAL] Se han encontrado %0d filas con errores.", err_count);
            $display("             Revisa la dirección del barrel shifter o si los datos tienen ruido.");
        end
        $display("=========================================================================");
        
        $finish;
    end

endmodule