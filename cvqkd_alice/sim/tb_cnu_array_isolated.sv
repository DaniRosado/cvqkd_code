`timescale 1ns / 1ps

module tb_cnu_array_isolated;

    parameter int Z = 384;
    parameter int W = 16;
    parameter int COL_W = 7;

    logic clk, rst_n;
    logic start_row, phase, valid_in;
    logic [COL_W-1:0] col_idx;
    
    // Buses para el array
    logic [Z*W-1:0] q_bus;
    logic [Z*W-1:0] q_bus_current;  // Registered version of q_bus (1-cycle delayed)
    logic [Z*W-1:0] p_bus;
    logic [Z-1:0]   syndrome_row;
    
    // Salidas
    wire [Z*W-1:0] r_new_bus;
    wire [Z-1:0]   row_syndrome;
    wire [Z-1:0]   row_syndrome_p;

    // q_bus_current is q_bus delayed by 1 cycle (simulates registered VNU output)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            q_bus_current <= '0;
        else
            q_bus_current <= q_bus;
    end

    // Memoria para cargar datos de MATLAB
    logic [Z*W-1:0] ram_q_in [0:67];
    logic [Z*W-1:0] ram_p_in [0:67];
    logic [Z*W-1:0] ram_r_expected [0:67];
    logic [383:0]   ram_syndrome_bob [0:45];

    // Instancia del Array completo
    cnu_min_sum_array #(
        .Z(Z), .W(W), .COL_W(COL_W)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start_row(start_row),
        .phase(phase),
        .valid_in(valid_in),
        .q_bus(q_bus),
        .q_bus_current(q_bus_current),
        .p_bus(p_bus),
        .col_idx(col_idx),
        .syndrome_row(syndrome_row),
        .r_new_bus(r_new_bus),
        .row_syndrome(row_syndrome),
        .row_syndrome_p(row_syndrome_p)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    int total_mismatches = 0;
    
    initial begin
        $display("[TB] Cargando vectores de MATLAB...");
        $readmemb("C:/Users/usser/TFG/cvqkd_code/cvqkd_matlab/data/cnu_tb_q_in.txt", ram_q_in);
        $readmemb("C:/Users/usser/TFG/cvqkd_code/cvqkd_matlab/data/cnu_tb_p_in.txt", ram_p_in);
        $readmemb("C:/Users/usser/TFG/cvqkd_code/cvqkd_matlab/data/cnu_tb_r_out.txt", ram_r_expected);
        $readmemb("C:/Users/usser/TFG/cvqkd_code/cvqkd_matlab/data/expected_syndrome.txt", ram_syndrome_bob);

        rst_n = 0; start_row = 0; phase = 0; valid_in = 0; col_idx = 0;
        #50 rst_n = 1;
        @(posedge clk);

        // --- 1. Iniciar Fila 0 ---
        syndrome_row = {<<{ram_syndrome_bob[0]}};
        start_row = 1;
        @(posedge clk);
        start_row = 0;

        // --- 2. Fase de lectura ---
        for (int c = 0; c < 68; c++) begin
            valid_in = 1; phase = 0; col_idx = c;
            q_bus = ram_q_in[c];
            p_bus = ram_p_in[c];
            @(posedge clk);
        end
        valid_in = 0;
        @(posedge clk);

        // --- 3. Fase de escritura ---
        phase = 1;
        // Esperamos unos ciclos para que la lógica combinacional de los 384 nodos se estabilice
        // y aplique el escalado alpha tras ver la fila completa.
        #50; 
        
        $display("[INFO] Comparando resultados finales tras procesar toda la fila...");

        for (int c = 0; c < 68; c++) begin
            col_idx = c;
            @(posedge clk);

            // Comparamos el bus completo contra la columna c del golden reference
            if (r_new_bus !== ram_r_expected[c]) begin
                total_mismatches++;
                if (total_mismatches < 5) begin
                    $display("[FAIL] Mismatch final en Columna %0d", c);
                end
            end
        end
        
        if (total_mismatches == 0) begin
            $display("=================================================");
            $display("[SUCCESS] ¡CNU ARRAY FUNCIONA! Coincidencia total.");
            $display("=================================================");
        end else begin
            $display("=================================================");
            $display("[FAIL] La fila no coincide. Fallos encontrados: %0d", total_mismatches);
            $display("=================================================");
        end
        
        $display("[TB] Test finalizado.");
        $finish;
    end
endmodule