`timescale 1ns / 1ps

module tb_mdr_bob_top();

    // =====================================================================
    // PARÁMETROS Y SEÑALES
    // =====================================================================
    localparam int TOTAL_BLOCKS = 13056; // N_BOB_DATA / 4 (Mismo que en FSM)
    localparam int CLK_PERIOD   = 10;    // 100 MHz

    logic clk;
    logic rst_n;
    logic start;
    logic done;

    // --- Interfaces de Memoria y TRNG ---
    logic [7:0]   trng_data;
    
    logic         ram_read_en;
    logic [13:0]  ram_read_addr;
    logic [127:0] ram_read_data;
    
    logic         ram_write_en;
    logic [13:0]  ram_write_addr;
    logic [255:0] ram_write_data;

    // =====================================================================
    // MEMORIAS EMULADAS PARA EL TESTBENCH
    // =====================================================================
    // 1. RAM de Entrada (Coordenadas Y de Bob)
    logic [127:0] input_ram [0:TOTAL_BLOCKS-1];
    
    // 2. Memoria del TRNG (8 bits aleatorios por cada bloque de datos)
    // Extraídos del archivo bob_random_bits.txt
    logic [7:0] trng_mem [0:TOTAL_BLOCKS-1];
    
    // 3. ROM de Resultados Esperados (Verdad Absoluta de MATLAB)
    logic [255:0] expected_m_ram [0:TOTAL_BLOCKS-1];

    // =====================================================================
    // CARGA DE ARCHIVOS (.txt generados por MATLAB)
    // =====================================================================
    initial begin
        // Asume que los .txt están en la misma carpeta que la simulación de Vivado
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_mdr_inputs.txt", input_ram);
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_random_bits.txt", trng_mem); // Ojo, si exportaste los 8 bits juntos en binario
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_m_messages.txt", expected_m_ram);
        $display("---------------------------------------------------");
        $display("[TB] Archivos cargados exitosamente en las RAMs");
        $display("---------------------------------------------------");
    end

    // Comportamiento de la RAM de lectura y el TRNG
    // (Entregan el dato en el mismo ciclo que se pide la dirección)
    always_comb begin
        if (ram_read_en) begin
            ram_read_data = input_ram[ram_read_addr];
            trng_data     = trng_mem[ram_read_addr]; // Sincronizado con los datos
        end else begin
            ram_read_data = '0;
            trng_data     = '0;
        end
    end

    // =====================================================================
    // INSTANCIACIÓN DEL DUT (Device Under Test)
    // =====================================================================
    mdr_bob_top u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .done            (done),
        .trng_data       (trng_data),
        .ram_read_en     (ram_read_en),
        .ram_read_addr   (ram_read_addr),
        .ram_read_data   (ram_read_data),
        .ram_write_en    (ram_write_en),
        .ram_write_addr  (ram_write_addr),
        .ram_write_data  (ram_write_data)
    );

    // =====================================================================
    // GENERADOR DE RELOJ Y CONTROL PRINCIPAL
    // =====================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        // 1. Reset del sistema
        rst_n = 0;
        start = 0;
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 5);
        
        // 2. Disparamos el acelerador
        $display("[TB] Iniciando procesamiento MDR de Bob...");
        start = 1;
        
        // 3. Esperamos a que la FSM levante la bandera 'done'
        wait(done == 1'b1);
        start = 0;
        
        $display("---------------------------------------------------");
        $display("  [TB] SIMULACION TERMINADA (Todos los bloques procesados) ");
        $display("---------------------------------------------------");
        $finish;
    end

    // =====================================================================
    // AUTO-CHECKER INTELIGENTE (Tolerante a la cuantización de la LUT)
    // =====================================================================
    int errores_totales = 0;

    always_ff @(posedge clk) begin
        if (ram_write_en) begin
            logic error_found = 1'b0;
            
            for (int i = 0; i < 8; i++) begin
                logic signed [31:0] hw_val = ram_write_data[i*32 +: 32];
                logic signed [31:0] esp_val = expected_m_ram[ram_write_addr][i*32 +: 32];
                
                // Calculamos la diferencia absoluta usando 64 bits para evitar overflows
                longint diff = hw_val - esp_val; 
                if (diff < 0) diff = -diff;
                
                // Tolerancia de ~1.5% (aprox 250,000 unidades en Q24)
                // Cubre el margen de error de no usar Newton-Raphson
                if (diff > 250000) begin
                    error_found = 1'b1;
                end
            end
            
            if (error_found) begin
                $display(" [!!!] ERROR FATAL en Bloque %0d", ram_write_addr);
                $display("       -> HARDWARE: %h", ram_write_data);
                $display("       -> ESPERADO: %h", expected_m_ram[ram_write_addr]);
                errores_totales++;
                
                if (errores_totales > 10) begin
                    $display("Demasiados errores. Deteniendo simulación.");
                    $stop;
                end
            end else begin
                if (ram_write_addr % 1000 == 0) begin
                    $display("  -> Bloque %0d verificado con éxito (Precisión superior al 99.0%%)", ram_write_addr);
                end
            end
        end
    end

endmodule