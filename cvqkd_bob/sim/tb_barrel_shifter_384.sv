`timescale 1ns / 1ps

module tb_barrel_shifter_384;

    // 1. Declaración de señales
    logic [383:0] data_in;
    logic [8:0]   shift_val;
    logic [383:0] data_out;
    
    // Señal interna del TB para comprobación
    logic [383:0] expected_out;

    // 2. Instanciación del Unit Under Test (UUT)
    barrel_shifter_384 uut (
        .data_in(data_in),
        .shift_val(shift_val),
        .data_out(data_out)
    );

    // 3. Bloque de estímulos y verificación
    initial begin
        $display("=================================================");
        $display(" Iniciando Testbench: Barrel Shifter Logarítmico ");
        $display("=================================================");
        
        // Inicializamos la entrada con un patrón muy reconocible.
        // Ponemos un '1' aislado en el bit 0, y el patrón 'F' (1111) en los bits más altos.
        data_in = '0;
        data_in[0] = 1'b1;
        data_in[383:380] = 4'hF;

        // Bucle de escaneo: Probamos desplazamientos saltando de 15 en 15 posiciones
        for (int i = 0; i < 384; i = i + 15) begin
            shift_val = i;
            
            // Esperamos 10 ns para que la lógica combinacional se propague
            #10; 

            // El TB calcula cuál debería ser el resultado exacto (Shift circular a la derecha)
            if (i == 0) begin
                expected_out = data_in;
            end else begin
                // Rotación circular dinámica legal en SystemVerilog
                expected_out = (data_in >> i) | (data_in << (384 - i));
            end

            // Comprobación automática
            if (data_out !== expected_out) begin
                $display("[ERROR] Fallo crítico en shift_val = %0d.", i);
                $display("        Esperado: %h", expected_out);
                $display("        Obtenido: %h", data_out);
                $stop; // Detenemos la simulación si hay fallo
            end else begin
                $display("[OK] Shift de %0d posiciones comprobado.", i);
            end
        end

        $display("-------------------------------------------------");
        $display(" Ejecutando pruebas específicas de la matriz BG1 ");
        
        // Prueba específica con el primer valor problemático de tu ROM
        shift_val = 307;
        #10;
        expected_out = {data_in[306 : 0], data_in[383 : 307]};
        
        if (data_out === expected_out) begin
            $display("[OK] Prueba BG1 (shift = 307) superada.");
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