`timescale 1ns / 1ps

module tb_mac_variance();

    // =========================================================================
    // 1. Declaración de Señales
    // =========================================================================
    logic               clk;
    logic               rst;
    logic               clear;
    logic               enable;
    logic signed [15:0] data_in;
    
    logic signed [63:0] sum_sq;
    logic signed [63:0] sum_val;

    // =========================================================================
    // 2. Instanciación del DUT (Device Under Test)
    // =========================================================================
    mac_variance dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(enable),
        .data_in(data_in),
        .sum_sq(sum_sq),
        .sum_val(sum_val)
    );

    // =========================================================================
    // 3. Generación de Reloj (100 MHz -> Periodo de 10ns)
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // 4. Estímulos y Autoverificación
    // =========================================================================
    initial begin
        // A) ESTADO INICIAL
        rst     = 1'b1;
        clear   = 1'b0;
        enable  = 1'b0;
        data_in = '0;
        
        #20; // Esperamos 2 ciclos de reloj
        rst = 1'b0;
        
        $display("---------------------------------------------------");
        $display("[INFO] Iniciando Test de Calculador de Varianza...");

        // B) INYECCIÓN DE DATOS (Pipeline continuo)
        // Vamos a inyectar los datos en cada flanco de subida sin parar
        @(posedge clk);
        enable <= 1'b1; data_in <= 16'sd2;   // Inyectamos un 2 positivo
        
        @(posedge clk);
        enable <= 1'b1; data_in <= -16'sd3;  // Inyectamos un 3 negativo
        
        @(posedge clk);
        enable <= 1'b1; data_in <= 16'sd4;   // Inyectamos un 4 positivo
        
        @(posedge clk);
        enable <= 1'b1; data_in <= -16'sd5;  // Inyectamos un 5 negativo

        // Dejamos de inyectar datos
        @(posedge clk);
        enable  <= 1'b0;
        data_in <= '0;

        // C) ESPERA DEL PIPELINE
        // Nuestro bloque tiene 3 etapas de pipeline. 
        // Esperamos unos 5 ciclos para estar 100% seguros de que los datos 
        // han cruzado todos los registros y se han sumado.
        repeat(5) @(posedge clk);

        // D) COMPROBACIÓN DE RESULTADOS
        $display("[INFO] Resultados tras procesar [ 2, -3, 4, -5 ]:");
        $display("       -> Sumatorio simple esperado : -2  | Obtenido: %0d", sum_val);
        $display("       -> Sumatorio cuad. esperado  : 54  | Obtenido: %0d", sum_sq);

        if (sum_val == -2 && sum_sq == 54) begin
            $display(" ");
            $display("  [ OK ] ¡CHECK MATEMÁTICO SUPERADO! ");
            $display("         El bloque maneja signos y pipelines correctamente.");
            $display(" ");
        end else begin
            $display(" ");
            $display("  [ X ]  ¡FALLO EN EL HARDWARE! ");
            $display(" ");
        end
        
        // E) PRUEBA DEL CLEAR (Limpieza entre tramas)
        $display("[INFO] Probando la senal de CLEAR...");
        clear <= 1'b1;
        @(posedge clk);
        clear <= 1'b0;
        
        @(posedge clk); // Esperamos a que los acumuladores se actualicen
        
        if (sum_val == 0 && sum_sq == 0) begin
            $display("  [ OK ] El hardware se ha reseteado correctamente.");
        end else begin
            $display("  [ X ]  Error en el CLEAR.");
        end

        $display("---------------------------------------------------");
        $finish;
    end

endmodule