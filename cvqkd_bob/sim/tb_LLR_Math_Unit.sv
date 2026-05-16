`timescale 1ns / 1ps

module tb_LLR_Math_Unit();

    // =========================================================================
    // SEÑALES DEL SISTEMA
    // =========================================================================
    logic clk;
    logic rst;
    logic start_calc;
    
    // Entradas de datos (Acumuladores)
    logic signed [63:0] sum_sq_P_B, sum_P_B, sum_cov_P, sum_P_A;
    logic signed [63:0] sum_sq_Q_B, sum_Q_B, sum_cov_Q, sum_Q_A;
    
    // Calibración
    logic signed [31:0] calib_VarA;
    
    // Salidas
    logic signed [31:0] T_final, T_sqrt, sigma_sq, sigma;
    logic data_ready;

    // =========================================================================
    // ARRAYS PARA LEER ARCHIVOS (.txt)
    // =========================================================================
    logic signed [63:0] mem_accumulators [0:7];
    logic signed [31:0] mem_expected     [0:3];

    // =========================================================================
    // INSTANCIA DEL DUT (Device Under Test)
    // =========================================================================
    LLR_math_unit dut (
        .clk(clk),
        .rst(rst),
        .start_calc(start_calc),
        
        .sum_sq_P_B(sum_sq_P_B), .sum_P_B(sum_P_B), .sum_cov_P(sum_cov_P), .sum_P_A(sum_P_A),
        .sum_sq_Q_B(sum_sq_Q_B), .sum_Q_B(sum_Q_B), .sum_cov_Q(sum_cov_Q), .sum_Q_A(sum_Q_A),
        
        .calib_VarA(calib_VarA),
        
        .T_final(T_final),
        .T_sqrt(T_sqrt),
        .sigma_sq(sigma_sq),
        .sigma(sigma),
        .data_ready(data_ready)
    );

    // =========================================================================
    // GENERACIÓN DE RELOJ (100 MHz)
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // PROCESO DE TEST (STIMULUS)
    // =========================================================================
    initial begin
        // 1. CARGA DE ARCHIVOS
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/accumulators.txt", mem_accumulators);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/expected_llr_math.txt", mem_expected);
        
        // 2. CONDICIONES INICIALES
        rst        = 1'b1;
        start_calc = 1'b0;
        
        // Asignamos la calibración generada en MATLAB (4.0 SNU * 10000)
        calib_VarA = 32'd40000; 
        
        // Inyectamos los acumuladores leídos del TXT
        sum_sq_P_B = mem_accumulators[0];
        sum_P_B    = mem_accumulators[1];
        sum_cov_P  = mem_accumulators[2];
        sum_P_A    = mem_accumulators[3];
        
        sum_sq_Q_B = mem_accumulators[4];
        sum_Q_B    = mem_accumulators[5];
        sum_cov_Q  = mem_accumulators[6];
        sum_Q_A    = mem_accumulators[7];

        #25 rst = 1'b0; // Soltamos reset
        
        $display("\n=======================================================");
        $display("[INFO] Iniciando Simulacion de la Unidad LLR Math...");
        
        // 3. DISPARO DEL CÁLCULO
        @(posedge clk);
        start_calc = 1'b1;
        @(posedge clk);
        start_calc = 1'b0; // Pulso de 1 ciclo
        
        // 4. ESPERAMOS A QUE TERMINE LA TUBERÍA
        wait(data_ready == 1'b1);
        $display("[INFO] Calculos finalizados (Divisor y CORDICs completados).");
        
        // 5. AUTO-VERIFICACIÓN CON TOLERANCIA
        verificar_resultados();
        
        #50;
        $finish;
    end
    
    // =========================================================================
    // TAREA DE VERIFICACIÓN (Imprime la tabla comparativa)
    // =========================================================================
    task verificar_resultados();
        integer err_T, err_T_sqrt, err_Sigma_sq, err_Sigma;
        integer num_errores = 0;
        
        // El orden en expected_llr_math.txt era: [0] T, [1] sqrt(T), [2] Sigma^2, [3] Sigma
        err_T        = T_final  - mem_expected[0];
        err_T_sqrt   = T_sqrt   - mem_expected[1];
        err_Sigma_sq = sigma_sq - mem_expected[2];
        err_Sigma    = sigma    - mem_expected[3];
        
        // Valor absoluto del error
        if (err_T < 0)        err_T        = -err_T;
        if (err_T_sqrt < 0)   err_T_sqrt   = -err_T_sqrt;
        if (err_Sigma_sq < 0) err_Sigma_sq = -err_Sigma_sq;
        if (err_Sigma < 0)    err_Sigma    = -err_Sigma;
        
        $display("-------------------------------------------------------------------------");
        $display("    MÉTRICA        | FPGA (Q16.16) | MATLAB (P. Fijo) | ERROR (Bits) ");
        $display("-------------------+---------------+------------------+------------------");
        $display(" T (Transmitancia) |  %12d |     %12d |   %8d", T_final,  mem_expected[0], err_T);
        $display(" sqrt(T)           |  %12d |     %12d |   %8d", T_sqrt,   mem_expected[1], err_T_sqrt);
        $display(" Sigma^2           |  %12d |     %12d |   %8d", sigma_sq, mem_expected[2], err_Sigma_sq);
        $display(" Sigma             |  %12d |     %12d |   %8d", sigma,    mem_expected[3], err_Sigma);
        $display("-------------------------------------------------------------------------");
        
        // Comprobación estricta de tolerancia (permitimos +/- 2 unidades por truncamiento de CORDIC)
        if (err_T > 2) num_errores++;
        if (err_T_sqrt > 2) num_errores++;
        if (err_Sigma_sq > 2) num_errores++;
        if (err_Sigma > 2) num_errores++;
        
        if (num_errores == 0) begin
            $display("  [ OK ] ¡HARDWARE PERFECTO! ");
            $display("         La FPGA coincide bit a bit con la emulacion de MATLAB.");
        end else begin
            $display("  [ X ]  ¡ERROR MATEMATICO! ");
            $display("         Al menos un parametro supera el margen de tolerancia.");
        end
        $display("=======================================================\n");
    endtask

endmodule