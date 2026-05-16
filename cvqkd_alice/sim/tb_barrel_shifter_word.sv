`timescale 1ns / 1ps

module tb_barrel_shifter_word;

    // =========================================================================
    // 1. Parámetros y Señales
    // =========================================================================
    parameter int Z = 384;
    parameter int W = 8;
    localparam int TOTAL_BITS = Z * W; // 3072 bits

    logic [TOTAL_BITS-1:0] data_in;
    logic [8:0]            shift_val;
    logic [TOTAL_BITS-1:0] data_out;
    
    // Señal interna del TB para la comprobación automática
    logic [TOTAL_BITS-1:0] expected_out;

    // =========================================================================
    // 2. Instanciación del Unit Under Test (UUT)
    // =========================================================================
    barrel_shifter_word #(
        .Z(Z),
        .W(W)
    ) uut (
        .data_in(data_in),
        .shift_val(shift_val),
        .data_out(data_out)
    );

    // =========================================================================
    // 3. Bloque de Estímulos y Verificación
    // =========================================================================
    initial begin
        $display("=================================================");
        $display(" Iniciando Testbench: Word-Level Barrel Shifter  ");
        $display("=================================================");
        
        // 1. Inicialización de datos con un patrón reconocible
        // Rellenamos cada "palabra" de 8 bits con su índice (0 a 255)
        // Como Z=384, a partir del 256 el patrón se reiniciará (overflow natural de 8 bits)
        data_in = '0;
        for (int i = 0; i < Z; i++) begin
            // Insertamos el valor 'i' en el trozo correspondiente del bus gigante
            data_in[i*W +: W] = i[7:0]; 
        end

        // 2. Bucle de escaneo: Probamos desplazamientos saltando de 15 en 15 palabras
        for (int i = 0; i < Z; i = i + 15) begin
            shift_val = i;
            
            // Esperamos 10 ns para que la lógica combinacional de las 9 capas se propague
            #10; 

            // 3. El TB calcula el resultado exacto desplazando bloques de W bits
            if (i == 0) begin
                expected_out = data_in;
            end else begin
                // Desplazamiento circular multiplicando por el ancho de palabra (W)
                expected_out = (data_in >> (i * W)) | (data_in << (TOTAL_BITS - (i * W)));
            end

            // 4. Comprobación automática
            if (data_out !== expected_out) begin
                $display("[ERROR] Fallo crítico desplazando %0d palabras.", i);
                $stop; // Detenemos la simulación si hay fallo
            end else begin
                $display("[OK] Shift de %0d palabras ( %0d cables ) comprobado.", i, i*W);
            end
        end

        $display("-------------------------------------------------");
        $display(" Ejecutando pruebas específicas de la matriz BG1 ");
        
        // Prueba específica con valores de tu BG_ROM (ej. rotar 307 posiciones)
        shift_val = 307;
        #10;
        expected_out = (data_in >> (307 * W)) | (data_in << (TOTAL_BITS - (307 * W)));
        
        if (data_out === expected_out) begin
            $display("[OK] Prueba de red de permutación (shift = 307) superada.");
        end else begin
            $display("[ERROR] Fallo en la prueba de matriz (shift = 307).");
            $stop;
        end

        $display("=================================================");
        $display(" SIMULACIÓN COMPLETADA SIN ERRORES               ");
        $display("=================================================");
        
        $finish; // Terminamos la simulación
    end

endmodule