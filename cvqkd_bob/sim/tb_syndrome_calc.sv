`timescale 1ns / 1ps

import bg_rom_pkg::*;

module tb_syndrome_calc;

    // =========================================================================
    // 1. Declaración de Señales
    // =========================================================================
    logic         clk;
    logic         rst_n;
    logic         start;
    
    logic [6:0]   u_addr;
    logic [383:0] u_data_in;
    
    logic         done;
    logic [383:0] syndrome_out [0:MB-1];

    // =========================================================================
    // 2. Memorias del Testbench y Emulación de BRAM
    // =========================================================================
    // Memoria para almacenar el vector de entrada U (68 bloques)
    logic [383:0] ram_u_bits [0:NB-1];
    
    // Memoria para almacenar el resultado correcto esperado (46 bloques)
    logic [383:0] ram_expected_s [0:MB-1];

    // Carga de los ficheros de texto generados por MATLAB
    initial begin
        $readmemb("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/u_bits.txt", ram_u_bits);
        $readmemb("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/expected_syndrome.txt", ram_expected_s);
    end

    // Emulación de una Block RAM síncrona real (Latencia de 1 ciclo)
    always_ff @(posedge clk) begin
        u_data_in <= ram_u_bits[u_addr];
    end

    // =========================================================================
    // 3. Instanciación del Unit Under Test (UUT)
    // =========================================================================
    syndrome_calc_bg1 uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .u_addr(u_addr),
        .u_data_in(u_data_in),
        .done(done),
        .syndrome_out(syndrome_out)
    );

    // =========================================================================
    // 4. Generación de Reloj y Ciclo de Vida del Test
    // =========================================================================
    // Reloj de 100 MHz (10 ns de periodo)
    initial clk = 0;
    always #5 clk = ~clk;

    int errores_totales = 0;

    initial begin
        $display("=================================================");
        $display(" Iniciando Verificación de Síndrome LDPC BG1     ");
        $display("=================================================");
        
        // Condiciones iniciales y Reset
        rst_n = 0;
        start = 0;
        
        #50;        // Esperamos 5 ciclos de reloj
        rst_n = 1;  // Liberamos el reset
        #20;
        
        // Disparamos el pulso de inicio para la FSM
        start = 1;
        #10;
        start = 0;
        
        $display("[INFO] Máquina de estados en marcha. Procesando %0d columnas...", NB);
        
        // Esperamos dinámicamente hasta que la FSM levante la bandera 'done'
        wait(done == 1'b1);
        
        $display("[INFO] Cálculo completado. Iniciando escaneo de errores...");
        $display("-------------------------------------------------");
        
        // Bucle de comprobación de los 46 bloques (17.664 bits)
        for (int i = 0; i < MB; i++) begin
            if (syndrome_out[i] !== ram_expected_s[i]) begin
                $display("[FAIL] Discrepancia en la fila %0d", i);
                $display("       Esperado: %h", ram_expected_s[i]);
                $display("       Obtenido: %h", syndrome_out[i]);
                errores_totales++;
            end
        end
        
        // Veredicto Final
        $display("-------------------------------------------------");
        if (errores_totales == 0) begin
            $display("[SUCCESS] Verificación de hardware PERFECTA.");
            $display("          Los 17.664 bits del síndrome coinciden exactamente.");
        end else begin
            $display("[CRITICAL] Se han encontrado %0d filas con errores.", errores_totales);
        end
        $display("=================================================");
        
        $finish;
    end

endmodule