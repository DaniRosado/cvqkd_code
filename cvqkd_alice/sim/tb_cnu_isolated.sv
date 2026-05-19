`timescale 1ns / 1ps

module tb_cnu_isolated;

    // Parámetros de arquitectura
    parameter int Z = 384;
    parameter int W = 16;
    parameter int COL_W = 7;

    logic clk, rst_n;
    
    // Señales de control que imitan la FSM
    logic start_row;
    logic phase;
    logic valid_in;
    logic [COL_W-1:0] col_idx;
    
    // Buses de datos gigantes
    logic [Z*W-1:0] q_bus;
    logic [Z*W-1:0] p_bus;
    logic [Z-1:0]   syndrome_row;
    
    // Salidas a verificar
    wire [Z*W-1:0] r_new_bus;
    wire [Z-1:0]   row_syndrome;
    wire [Z-1:0]   row_syndrome_p;

    // Memorias RAM para el Testbench
    logic [Z*W-1:0] ram_q_in [0:67];
    logic [Z*W-1:0] ram_p_in [0:67];
    logic [Z*W-1:0] ram_r_expected [0:67];
    logic [383:0]   ram_syndrome_bob [0:45];

    // Instancia del módulo bajo prueba (DUT)
    cnu_min_sum_array #(
        .Z(Z), .W(W), .COL_W(COL_W)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start_row(start_row),
        .phase(phase),
        .valid_in(valid_in),
        .q_bus(q_bus),
        .q_bus_current(q_bus), // Se mapean igual para aislar la prueba combinacional
        .p_bus(p_bus),
        .col_idx(col_idx),
        .syndrome_row(syndrome_row),
        .r_new_bus(r_new_bus),
        .row_syndrome(row_syndrome),
        .row_syndrome_p(row_syndrome_p)
    );

    // Generador de reloj (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // Proceso principal de carga y estímulos
    initial begin
        $display("=============================================");
        $display(" INICIANDO TESTBENCH AISLADO DE CNU (384 nodos)");
        $display("=============================================");

        // 1. Cargar vectores de prueba desde MATLAB
        $readmemb("cnu_tb_q_in.txt", ram_q_in);
        $readmemb("cnu_tb_p_in.txt", ram_p_in);
        $readmemb("cnu_tb_r_out.txt", ram_r_expected);
        $readmemb("expected_syndrome.txt", ram_syndrome_bob); // Reciclamos tu archivo del top

        // 2. Inicialización
        rst_n = 0;
        start_row = 0; phase = 0; valid_in = 0; col_idx = 0;
        q_bus = '0; p_bus = '0; syndrome_row = '0;
        
        #50 rst_n = 1; // Soltar reset
        #20;

        // 3. Imitar el inicio de la Fila 0
        $display("[INFO] Alimentando Fila 0 (Iteracion 1)...");
        syndrome_row = {<<{ram_syndrome_bob[0]}}; // Aplicamos el Endianness correcto de Bob
        start_row = 1;
        @(posedge clk);
        start_row = 0;

        // 4. Fase de LECTURA (Barrer las 68 columnas)
        for (int c = 0; c < 68; c++) begin
            valid_in = 1;
            phase    = 0;
            col_idx  = 7'(c);
            q_bus    = ram_q_in[c];
            p_bus    = ram_p_in[c];
            
            @(posedge clk);
        end

        // Cerrar entradas
        valid_in = 0;
        q_bus = '0; p_bus = '0;
        
        // Simular el ciclo extra de DRAIN si tu arquitectura lo usa
        @(posedge clk); 

        // 5. Fase de ESCRITURA (Leer R_new y comparar)
        $display("[INFO] Iniciando fase de escritura y comprobación...");
        phase = 1; // Avisamos a los CNUs que escupan el resultado

        for (int c = 0; c < 68; c++) begin
            int mismatches = 0;
            
            // Volvemos a pasar el índice de columna para que el CNU multiplexe el R_new
            col_idx = 7'(c);
            #1; // Pequeño delay delta para que se propague el combinacional
            
            // Comparar los 384 Nodos
            for (int z = 0; z < Z; z++) begin
                logic [W-1:0] r_got = r_new_bus[z*W +: W];
                logic [W-1:0] r_exp = ram_r_expected[c][z*W +: W];
                
                // Si usamos la matriz dispersa, comprobar solo los enlaces válidos
                // (Opcionalmente puedes incluir aquí el check de BG_ROM[0][c] != -1)
                
                if (r_got !== r_exp) begin
                    mismatches++;
                    if (mismatches < 3) begin // Mostrar solo un par por columna
                        $display("[ERROR] Col %0d, Nodo %0d: Esperado %b, Obtenido %b", c, z, r_exp, r_got);
                    end
                end
            end
            
            if (mismatches > 0) begin
                $display("[FAIL] La Columna %0d tiene %0d fallos en los mensajes R.", c, mismatches);
            end else begin
                $display("[OK] Columna %0d coincide 100%%", c);
            end
            
            @(posedge clk);
        end
        
        $display("[INFO] Comprobando Síndrome de la Fila...");
        // El síndrome final debería ser todo ceros si P estaba corregido, 
        // o un patrón específico si estamos en Iter 1.
        $display("       Síndrome Residual: %b", row_syndrome_p);

        $display("=============================================");
        $display(" TEST FINALIZADO.");
        $display("=============================================");
        $finish;
    end

endmodule