`timescale 1ns / 1ps

module tb_cnu_array_isolated;

    parameter int Z = 384;
    parameter int W = 16;
    parameter int COL_W = 7;
    parameter int N_COLS = 68;

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
    logic [Z*W-1:0] ram_q_in [0:N_COLS-1];
    logic [Z*W-1:0] ram_p_in [0:N_COLS-1];
    logic [Z*W-1:0] ram_r_expected [0:N_COLS-1];
    logic [383:0]   ram_syndrome_bob [0:45];

    // BG matrix row 0 validity mask (columns with shift != -1)
    // Row 0: cols 0-23 are valid, cols 24-67 are -1 (no edge)
    logic col_valid [0:N_COLS-1];

    function automatic void init_col_valid();
        // BG_ROM row 0 shift values from bg_rom_pkg
        // Valid columns (shift != -1): 0-23
        // Invalid columns (shift == -1): 24-67
        for (int c = 0; c < N_COLS; c++) begin
            col_valid[c] = (c < 24);  // Row 0 has 24 valid columns
        end
    endfunction

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
    int valid_count;
    
    initial begin
        $display("[TB] Cargando vectores de MATLAB...");
        $readmemb("C:/Users/usser/TFG/cvqkd_code/cvqkd_matlab/data/cnu_tb_q_in.txt", ram_q_in);
        $readmemb("C:/Users/usser/TFG/cvqkd_code/cvqkd_matlab/data/cnu_tb_p_in.txt", ram_p_in);
        $readmemb("C:/Users/usser/TFG/cvqkd_code/cvqkd_matlab/data/cnu_tb_r_out.txt", ram_r_expected);
        $readmemb("C:/Users/usser/TFG/cvqkd_code/cvqkd_matlab/data/expected_syndrome.txt", ram_syndrome_bob);

        rst_n = 0; start_row = 0; phase = 0; valid_in = 0; col_idx = 0;
        #50 rst_n = 1;
        @(posedge clk);

        // Initialize column validity mask
        init_col_valid();

        // --- 1. Iniciar Fila 0 ---
        syndrome_row = {<<{ram_syndrome_bob[0]}};
        start_row = 1;
        @(posedge clk);
        start_row = 0;

        // --- 2. Fase de lectura (solo columnas válidas) ---
        valid_count = 0;
        for (int c = 0; c < N_COLS; c++) begin
            if (col_valid[c]) begin
                valid_in = 1; phase = 0; col_idx = c;
                q_bus = ram_q_in[c];
                p_bus = ram_p_in[c];
                valid_count++;
            end else begin
                valid_in = 0;
                q_bus = '0;
                p_bus = '0;
            end
            @(posedge clk);
        end
        valid_in = 0;
        @(posedge clk);

        $display("[INFO] Procesadas %0d columnas válidas de %0d totales", valid_count, N_COLS);

        // --- 3. Fase de escritura ---
        phase = 1;
        #50; 
        
        $display("[INFO] Comparando resultados finales tras procesar toda la fila...");

        // Debug: check Q inputs for column 0
        $display("[DBG] Q inputs Col 0: q_bus[0]=%b (sign=%b mag=%d)",
                 ram_q_in[0][0*W +: W], ram_q_in[0][0*W + W-1], ram_q_in[0][0*W +: W-1]);
        $display("[DBG] Q inputs Col 0: q_bus[1]=%b (sign=%b mag=%d)",
                 ram_q_in[0][1*W +: W], ram_q_in[0][1*W + W-1], ram_q_in[0][1*W +: W-1]);
        $display("[DBG] Q inputs Col 0: q_bus[383]=%b (sign=%b mag=%d)",
                 ram_q_in[0][383*W +: W], ram_q_in[0][383*W + W-1], ram_q_in[0][383*W +: W-1]);

        // Debug: check first few nodes for column 0
        $display("[DBG] Col 0: RTL r_new[0]=%b (sign=%b mag=%d), exp=%b (sign=%b mag=%d)",
                 r_new_bus[0*W +: W], r_new_bus[0*W + W-1], r_new_bus[0*W +: W-1],
                 ram_r_expected[0][0*W +: W], ram_r_expected[0][0*W + W-1], ram_r_expected[0][0*W +: W-1]);
        $display("[DBG] Col 0: RTL r_new[1]=%b, exp=%b",
                 r_new_bus[1*W +: W], ram_r_expected[0][1*W +: W]);

        for (int c = 0; c < N_COLS; c++) begin
            col_idx = c;
            @(posedge clk);

            if (col_valid[c]) begin
                // Comparamos solo columnas válidas
                if (r_new_bus !== ram_r_expected[c]) begin
                    total_mismatches++;
                    if (total_mismatches < 5) begin
                        $display("[FAIL] Mismatch en Columna válida %0d", c);
                    end
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