`timescale 1ns / 1ps

module tb_cvqkd_bob_dsp_top();

    // =========================================================================
    // 1. Declaración de Parámetros y Señales
    // =========================================================================
    localparam ADC_WIDTH = 16;
    localparam NUM_SAMPLES_IN = 55713;  
    localparam NUM_SAMPLES_OUT = 52230; 

    logic clk;
    logic rst;
    
    logic signed [ADC_WIDTH-1:0] p_in, q_in;
    logic                        valid_in;
    logic signed [ADC_WIDTH-1:0] p_out, q_out;
    logic                        valid_out;

    // Memorias
    logic [31:0] memoria_in [0:NUM_SAMPLES_IN-1];
    logic [31:0] memoria_expected [0:NUM_SAMPLES_OUT-1];
    logic [31:0] mem_pilotos_esperados [0:3500]; 
    logic [31:0] mem_fase_estimada [0:NUM_SAMPLES_OUT-1]; // NUEVO ARCHIVO
    
    integer file_out, file_err, file_phase;

    // --- Contadores Datos ---
    integer out_counter = 0;   
    integer expected_idx = 0;  
    integer error_counter = 0; 
    logic signed [15:0] exp_q, exp_p;
    integer diff_p, diff_q, abs_diff_p, abs_diff_q; 

    // --- Contadores Pilotos ---
    integer piloto_count = 0;
    logic signed [17:0] fase_esperada;
    integer error_fase, max_error_fase = 0, sum_error_fase = 0, pilotos_fuera_margen = 0;

    // --- Contadores Interpolador ---
    integer fase_datos_count = 0;
    logic signed [17:0] fase_interpolada_esperada;
    integer error_fase_interp, max_error_interp = 0, errores_interp_count = 0;

    // =========================================================================
    // 2. Instanciación del DUT
    // =========================================================================
    cvqkd_bob_dsp_top #(
        .ADC_WIDTH(ADC_WIDTH)
    ) dut (
        .clk(clk), .rst(rst),
        .p_in(p_in), .q_in(q_in), .valid_in(valid_in),
        .p_out(p_out), .q_out(q_out), .valid_out(valid_out)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    initial begin
        file_out = $fopen("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/sim_outputs.txt", "w");
        file_err = $fopen("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/sim_errors.txt", "w");
        file_phase = $fopen("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/sim_phase_interp.txt", "w");
    end

    // =========================================================================
    // VERIFICACIÓN DE DATOS FINALES (P y Q)
    // =========================================================================
    always_ff @(negedge clk) begin
        if (valid_out) begin
            $fdisplay(file_out, "%04x%04x", q_out[15:0], p_out[15:0]);

            if (expected_idx < 52224) begin
                exp_q = memoria_expected[expected_idx][31:16];
                exp_p = memoria_expected[expected_idx][15:0];
                diff_p = $signed(p_out) - exp_p;
                diff_q = $signed(q_out) - exp_q;
    
                if (file_err != 0) $fdisplay(file_err, "%0d %0d %0d", out_counter, diff_p, diff_q);

                abs_diff_p = (diff_p < 0) ? -diff_p : diff_p;
                abs_diff_q = (diff_q < 0) ? -diff_q : diff_q;

                if (abs_diff_p > 100 || abs_diff_q > 100) begin
                    $display("\n[STOP HW] ¡ERROR ENORME EN DATOS! Salida: %0d", out_counter);
                    //$stop; 
                end else if (abs_diff_p > 1 || abs_diff_q > 1) begin
                    error_counter++;
                end
                expected_idx++;
            end
            out_counter++;
        end
    end

    // =========================================================================
    // MONITOR 1: ESPÍA DE LOS PILOTOS (CORDIC 1)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (dut.cordic1_to_interp_valid) begin
            fase_esperada = mem_pilotos_esperados[piloto_count][17:0];
            error_fase = $signed(dut.cordic1_to_interp_theta) - fase_esperada;
            if (error_fase < 0) error_fase = -error_fase; 

            if (error_fase > max_error_fase) max_error_fase = error_fase;
            sum_error_fase = sum_error_fase + error_fase;

            if (error_fase > 10) pilotos_fuera_margen++;
            piloto_count++;
        end
    end

    // =========================================================================
    // MONITOR 2: ESPÍA DEL INTERPOLADOR DE FASE (Nuevo)
    // =========================================================================
    always_ff @(posedge clk) begin
        // Se activa cuando el interpolador envía un ángulo de dato válido a CORDIC 2
        if (dut.interp_cordic_valid) begin
            if (fase_datos_count < 52224) begin
                fase_interpolada_esperada = mem_fase_estimada[fase_datos_count][17:0];
                
                // IMPORTANTE: Le damos la vuelta al ángulo de Vivado porque está negado (-theta_raw)
                error_fase_interp = $signed(-dut.interp_cordic_theta) - fase_interpolada_esperada;
                
                // Guardamos en archivo para graficar en MATLAB
                if (file_phase != 0) begin
                    $fdisplay(file_phase, "%0d %0d %0d", fase_datos_count, $signed(-dut.interp_cordic_theta), fase_interpolada_esperada);
                end
                
                if (error_fase_interp < 0) error_fase_interp = -error_fase_interp;

                if (error_fase_interp > max_error_interp) max_error_interp = error_fase_interp;

                // Si la interpolación acumula más de 30 unidades de error, avisamos
                if (error_fase_interp > 30) begin
                    if (errores_interp_count < 15) begin 
                        $display("[WARNING INTERPOLADOR] Dato %0d -> MATLAB: %d | FPGA: %d (Error: %0d)", 
                                 fase_datos_count, fase_interpolada_esperada, $signed(-dut.interp_cordic_theta), error_fase_interp);
                    end
                    errores_interp_count++;
                end
            end
            fase_datos_count++;
        end
    end

    // =========================================================================
    // 5. INYECCIÓN DE DATOS Y VEREDICTO
    // =========================================================================
    initial begin
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/bob_raw_adc.txt", memoria_in);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/bob_ram.txt", memoria_expected);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/fase_pilotos_raw.txt", mem_pilotos_esperados);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/fase_estimada_datos.txt", mem_fase_estimada);

        rst = 1'b1; valid_in = 1'b0; p_in = '0; q_in = '0;
        #20; rst = 1'b0;
        
        for (int i = 0; i < NUM_SAMPLES_IN; i++) begin
            @(posedge clk);
            valid_in <= 1'b1;
            q_in <= memoria_in[i][31:16]; p_in <= memoria_in[i][15:0];
        end

        @(posedge clk); valid_in <= 1'b0; p_in <= '0; q_in <= '0;
        repeat(100) @(posedge clk);
        $fclose(file_out); if (file_err != 0) $fclose(file_err);
        if (file_phase != 0) $fclose(file_phase);
        
        $display("\n=================================================================");
        $display("                  REPORTE DE AUTOVERIFICACIÓN                    ");
        $display("=================================================================");
        
        $display("--> 1. PILOTOS (CORDIC 1)");
        $display("    Pilotos evaluados       : %0d", piloto_count);
        $display("    Error maximo detectado  : %0d unidades", max_error_fase);
        
        $display("\n--> 2. INTERPOLACIÓN (PHASE WRAP Y DIVISIÓN)");
        $display("    Datos interpolados      : %0d", fase_datos_count);
        $display("    Error max. acumulado    : %0d unidades", max_error_interp);
        if (errores_interp_count > 0)
            $display("    [ X ] ¡CUIDADO! La interpolacion se esta desviando (> 30 uds).");
        else
            $display("    [ OK ] Interpolacion precisa.");

        $display("\n--> 3. ROTACIÓN FINAL (CORDIC 2)");
        $display("    Errores P y Q (> 1 ud)  : %0d", error_counter);
        
        $display("=================================================================\n");
        $finish;
    end
endmodule