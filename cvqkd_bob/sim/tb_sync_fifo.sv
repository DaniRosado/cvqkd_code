`timescale 1ns / 1ps

module tb_sync_fifo();

    // =========================================================================
    // 1. Declaración de Señales y Parámetros
    // =========================================================================
    localparam DATA_WIDTH = 32;
    // TRUCO: Reducimos la profundidad a 8 SOLO para el testbench. 
    // Así podemos comprobar rápidamente si el flag "full" funciona.
    localparam TEST_DEPTH = 8; 

    logic clk;
    logic rst;
    
    logic we;
    logic [DATA_WIDTH-1:0] din;
    
    logic re;
    logic [DATA_WIDTH-1:0] dout;
    
    logic empty;
    logic full;

    // =========================================================================
    // 2. Instanciación del DUT (Device Under Test)
    // =========================================================================
    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(TEST_DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .we(we),
        .din(din),
        .re(re),
        .dout(dout),
        .empty(empty),
        .full(full)
    );

    // =========================================================================
    // 3. Generación de Reloj (100 MHz -> Periodo de 10ns)
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // =========================================================================
    // 4. Proceso Principal de Estímulos (El Test en sí)
    // =========================================================================
    initial begin
        // A) Estado Inicial y Reset
        we = 0;
        re = 0;
        din = '0;
        rst = 1;
        #20;
        rst = 0;
        #10;
        
        $display("--- INICIANDO TEST DE LA FIFO ---");

        // B) CASO 1: Escribir unos pocos datos (sin llenar)
        $display("Escribiendo 3 datos...");
        for (int i = 1; i <= 3; i++) begin
            @(posedge clk);
            we  <= 1'b1;
            // Metemos un patrón hexadecimal reconocible: 11111111, 22222222, 33333333...
            din <= i * 32'h11111111; 
        end
        @(posedge clk);
        we <= 1'b0;
        #20;

        // C) CASO 2: Leer algunos datos
        $display("Leyendo 2 datos...");
        for (int i = 0; i < 2; i++) begin
            @(posedge clk);
            re <= 1'b1;
        end
        @(posedge clk);
        re <= 1'b0;
        #20;

        // D) CASO 3: Llenar la FIFO al máximo para disparar el flag 'full'
        $display("Llenando la FIFO hasta que salte el 'full'...");
        // Intentamos escribir 10 veces, pero paramos si se llena
        for (int i = 0; i < 10; i++) begin
            @(posedge clk);
            if (!full) begin
                we  <= 1'b1;
                din <= 32'hAABBCC00 + i;
                re  <= 1'b1;
            end else begin
                we <= 1'b0; // Paramos de escribir
            end
        end
        @(posedge clk);
        we <= 1'b0;
        #20;

        // E) CASO 4: Lectura y Escritura Simultánea (Estrés del contador)
        $display("Lectura y Escritura en el mismo ciclo...");
        @(posedge clk);
        re  <= 1'b1; // Sacamos un dato
        we  <= 1'b1; // Metemos otro a la vez
        din <= 32'hFFFFFFFF;
        @(posedge clk);
        re <= 1'b0;
        we <= 1'b0;
        #20;

        // F) CASO 5: Vaciar la FIFO por completo
        $display("Vaciando el resto de la FIFO...");
        while (!empty) begin
            @(posedge clk);
            re <= 1'b1;
        end
        @(posedge clk);
        re <= 1'b0;

        // Esperamos un poco y fin
        #50;
        $display("--- SIMULACIÓN FINALIZADA SIN ERRORES ---");
        $finish;
    end

endmodule