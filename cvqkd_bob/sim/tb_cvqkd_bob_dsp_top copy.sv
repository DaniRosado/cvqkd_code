`timescale 1ns / 1ps

module tb_cvqkd_bob_dsp_top_2();

    // =========================================================================
    // 1. Declaración de Parámetros y Señales
    // =========================================================================
    localparam ADC_WIDTH     = 16;
    localparam TEST_SAMPLES   = 26112/2; // 13056
    localparam TOTAL_BOB_DATA = 26112;
    localparam NUM_SAMPLES_IN  = 55713;   // Trama con pilotos incluidos
    
    logic clk, rst;
    
    // Señales de Entrada del Sistema
    logic signed [ADC_WIDTH-1:0] p_in, q_in;
    logic                        valid_in;
    logic                        start_est;
    logic signed [31:0]          calib_VarA;
    logic                        mask_valid, mask_bit;
    logic                        alice_stream_valid;
    logic [31:0]                 alice_stream_data;
    
    // Señales de Monitoreo / Salida
    logic                        valid_key;
    logic [31:0]                 data_key;
    logic                        done_est, data_ready_est;
    logic signed [31:0]          T_est, T_sqrt_est, sigma_sq_est, sigma_est;

    // Buffers para volcar los .txt de MATLAB
    logic [31:0] mem_fiber      [0:NUM_SAMPLES_IN-1];
    logic        mem_mask       [0:TOTAL_BOB_DATA-1];
    logic [31:0] mem_alice      [0:TEST_SAMPLES-1];
    logic [31:0] mem_expected   [0:3];

    
    
    // =========================================================================
    // 2. Instanciación del DUT
    // =========================================================================
    cvqkd_bob_subsystem_top #(
        .ADC_WIDTH(ADC_WIDTH)
    ) dut (
        .clk(clk), .rst(rst),
        .p_in(p_in), .q_in(q_in), .valid_in(valid_in),
        .start_est(start_est), .calib_VarA(calib_VarA),
        .mask_valid(mask_valid), .mask_bit(mask_bit),
        .alice_stream_valid(alice_stream_valid), .alice_stream_data(alice_stream_data),
        .valid_key(valid_key), .data_key(data_key),
        .done_est(done_est), .data_ready_est(data_ready_est),
        .T_final(T_est), .T_sqrt(T_sqrt_est), .sigma_sq(sigma_sq_est), .sigma(sigma_est)
    );

    // Pipeline del Testbench para emparejar la transmisión clásica de Alice con el Router
    logic        alice_en_pipe;
    logic [31:0] alice_data_pipe;
    int          alice_read_idx = 0;

    initial begin clk = 0; forever #5 clk = ~clk; end

    initial begin
        $display("=========================================================================");
        $display("[TB FULL] Cargando datos avanzados de simulacion desde archivos...");
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_raw_adc.txt", mem_fiber);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/mask_bit.txt", mem_mask);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/alice_ram.txt", mem_alice);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_llr_math.txt", mem_expected);
        $display("[TB FULL] Archivos cargados. Liberando Reset...");

        // --- Fase 1: Inicialización de Buses ---
        clk = 0; rst = 1; valid_in = 0; p_in = 0; q_in = 0;
        start_est = 0; mask_valid = 0; mask_bit = 0;
        alice_stream_valid = 0; alice_stream_data = '0;
        alice_en_pipe = 0; alice_data_pipe = '0;
        calib_VarA = 32'd40000;

        #40 rst = 0;
        #40;
        
        for (int i = 0; i < NUM_SAMPLES_IN; i++) begin
            @(posedge clk);
            valid_in <= 1'b1;
            q_in <= mem_fiber[i][31:16]; p_in <= mem_fiber[i][15:0];
        end

        @(posedge clk); valid_in <= 1'b0; p_in <= '0; q_in <= '0;

        $display("[TB FULL] Datos de fibra transmitidos por completo. Esperando estabilizacion DSP...");

        // Damos un margen holgado para que el interpolador de fase y el CORDIC terminen de escribir
        #1000;

        @(posedge clk);
        for (int i = 0; i < TOTAL_BOB_DATA; i++) begin
            mask_valid = 1'b1;
            mask_bit   = mem_mask[i];
            
            // Si este bit de la máscara exige sacrificio, preparamos el dato de Alice para el ciclo (+1)
            if (mem_mask[i] == 1'b1) begin
                alice_en_pipe   = 1'b1;
                alice_data_pipe = mem_alice[alice_read_idx];
                alice_read_idx++;
            end else begin
                alice_en_pipe   = 1'b0;
                alice_data_pipe = 32'b0;
            end
            
            // Aplicamos el pipeline al puerto: se consolidará exactamente cuando el Router responda
            alice_stream_valid = alice_en_pipe;
            alice_stream_data  = alice_data_pipe;
            
            @(posedge clk);
        end
        
        // Vaciamos el residuo final del pipeline del TB
        mask_valid         = 1'b0;
        mask_bit           = 1'b0;
        alice_stream_valid = alice_en_pipe;
        alice_stream_data  = alice_data_pipe;
        @(posedge clk);
        alice_stream_valid = 1'b0;
        alice_stream_data  = '0;

        $display("[TB FULL] Mascara inyectada completamente. Esperando calculo asintotico final (done)...");
        
        // --- Fase 5: Validación de Resultados Matemáticos ---
        wait(done_est == 1'b1);
        @(posedge clk);
        
        begin
            integer err [4];
            err[0] = T_est        - mem_expected[0];
            err[1] = T_sqrt_est   - mem_expected[1];
            err[2] = sigma_sq_est - mem_expected[2];
            err[3] = sigma_est    - mem_expected[3];

            for(int i=0; i<4; i++) if(err[i] < 0) err[i] = -err[i];

            $display("-------------------------------------------------------------------------");
            $display("    METRICA CUANTICA  | FPGA (SUBSYSTEM) |  MATLAB (IDEAL)  | ERROR (Bits) ");
            $display("----------------------+------------------+------------------+------------------");
            $display(" Ganancia T_est       |     %12d |     %12d |     %8d", T_est,        mem_expected[0], err[0]);
            $display(" Raiz Sqrt(T)         |     %12d |     %12d |     %8d", T_sqrt_est,   mem_expected[1], err[1]);
            $display(" Varianza Sigma^2     |     %12d |     %12d |     %8d", sigma_sq_est, mem_expected[2], err[2]);
            $display(" Desviacion Sigma     |     %12d |     %12d |     %8d", sigma_est,    mem_expected[3], err[3]);
            $display("-------------------------------------------------------------------------");

            if (err[0]<=5 && err[1]<=5 && err[2]<=5 && err[3]<=5) begin
                $display("  [ OK ] ¡SISTEMA VALIDADO! El subsistema completo encaja de extremo a extremo.");
            end else begin
                $display("  [ X ]  ¡FALLO! Desajuste detectado en la integracion de flujo.");
            end
            $display("=========================================================================");
        end
        
        $finish;
    end
endmodule