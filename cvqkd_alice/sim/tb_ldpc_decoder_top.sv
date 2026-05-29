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
        .Z(Z), .W(W), .PIPELINE_DEPTH(2)
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
        #5000000; // Ajusta este tiempo si tu simulación es muy larga
        $display("[TB] ERROR CRÍTICO: Timeout alcanzado. La FSM no responde.");
        $finish;
    end

endmodule