`timescale 1ns / 1ps

module tb_cordic_rot_auto();

    // =========================================================================
    // Parámetros y Constantes
    // =========================================================================
    localparam NUM_SAMPLES_IN = 55713;  
    localparam NUM_SAMPLES_OUT = 52224; // Solo las muestras de datos recuperadas

    // Señales de reloj y reset
    logic clk;
    logic rst;

    // Entradas al CORDIC
    logic        s_axis_phase_tvalid;
    logic [23:0] s_axis_phase_tdata;
    logic        s_axis_cartesian_tvalid;
    logic [47:0] s_axis_cartesian_tdata;

    // Salidas del CORDIC
    logic        m_axis_dout_tvalid;
    logic [47:0] m_axis_dout_tdata;

    // =========================================================================
    // Memorias
    // =========================================================================
    logic [31:0] memoria_in [0:NUM_SAMPLES_IN-1];
    logic [31:0] memoria_expected [0:NUM_SAMPLES_OUT-1];
    logic [31:0] mem_fase_estimada [0:NUM_SAMPLES_OUT-1];
    
    // =========================================================================
    // Contadores e índices
    // =========================================================================
    integer data_idx = 0;       // Índice para los datos que enviamos al CORDIC
    integer out_idx = 0;        // Índice para comprobar lo que sale del CORDIC
    integer error_counter = 0;  // Contador de fallos
    
    // Variables para enviar datos
    logic signed [15:0] p_in, q_in;
    logic signed [17:0] phase_in;
    
    // Variables para recibir y comparar
    logic signed [15:0] out_P, out_Q;
    logic signed [15:0] exp_P, exp_Q;
    integer diff_p, diff_q, abs_diff_p, abs_diff_q;
    
    // Variable auxiliar para el cambio de signo
    logic signed [17:0] neg_phase_in;

    // Fichero de registro de errores
    integer file_err;

    // =========================================================================
    // Instancia del IP CORDIC de Rotación
    // =========================================================================
    cordic_rot_ip inst_cordic_rot (
        .aclk(clk),
        
        .s_axis_phase_tvalid(s_axis_phase_tvalid),
        .s_axis_phase_tdata(s_axis_phase_tdata),
        
        .s_axis_cartesian_tvalid(s_axis_cartesian_tvalid),
        .s_axis_cartesian_tdata(s_axis_cartesian_tdata),
        
        .m_axis_dout_tvalid(m_axis_dout_tvalid),
        .m_axis_dout_tdata(m_axis_dout_tdata)
    );

    // =========================================================================
    // Generación de Reloj
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // Monitor (Recepción y Validación)
    // =========================================================================
    always_ff @(negedge clk) begin
        if (m_axis_dout_tvalid) begin
            if (out_idx < NUM_SAMPLES_OUT) begin
                // Extraemos la salida del CORDIC (Mantenemos la extracción clásica de los LSBs)
                out_P = m_axis_dout_tdata[15:0];  
                out_Q = m_axis_dout_tdata[39:24];
                
                // Leemos lo que debería salir según MATLAB
                exp_Q = memoria_expected[out_idx][31:16];
                exp_P = memoria_expected[out_idx][15:0];
                
                // Calculamos error
                diff_p = $signed(out_P) - $signed(exp_P);
                diff_q = $signed(out_Q) - $signed(exp_Q);
                
                abs_diff_p = (diff_p < 0) ? -diff_p : diff_p;
                abs_diff_q = (diff_q < 0) ? -diff_q : diff_q;
                
                // Guardar SIEMPRE en el archivo (Índice, Fase Inyectada, Diff_P, Diff_Q, Exp_P, Exp_Q, Out_P, Out_Q)
                if (file_err != 0) begin
                    $fdisplay(file_err, "%0d %0d %0d %0d %0d %0d %0d %0d", 
                              out_idx, 
                              $signed(mem_fase_estimada[out_idx][17:0]), 
                              diff_p, diff_q, 
                              $signed(exp_P), $signed(exp_Q), 
                              $signed(out_P), $signed(out_Q));
                end

                // Avisamos si hay error grande (margen de 1 unidad)
                if (abs_diff_p > 1 || abs_diff_q > 1) begin
                    error_counter++;
                    if (error_counter <= 20) begin
                        $display("[ERROR %0d] Muestra DATA_%0d -> Entrada Fase=%0d, P_in=%0d, Q_in=%0d | Esperado P=%0d Q=%0d | SALIDA CORDIC P=%0d Q=%0d (Diff P=%0d, Q=%0d)",
                                 error_counter, out_idx, 
                                 $signed(mem_fase_estimada[out_idx][17:0]), // Fase original que le inyectamos
                                 $signed(memoria_in[out_idx + (out_idx/15) + 1][15:0]), // Estimación rústica de índices
                                 $signed(memoria_in[out_idx + (out_idx/15) + 1][31:16]),
                                 $signed(exp_P), $signed(exp_Q),
                                 $signed(out_P), $signed(out_Q), diff_p, diff_q);
                    end
                end
                
                out_idx++;
            end
        end
    end

    // =========================================================================
    // Estímulos (Inyección de Datos)
    // =========================================================================
    initial begin
        // 1. Cargar Archivos
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/bob_raw_adc.txt", memoria_in);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/bob_ram.txt", memoria_expected);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/fase_estimada_datos.txt", mem_fase_estimada);

        // Inicialización
        rst = 1;
        s_axis_phase_tvalid = 0;
        s_axis_cartesian_tvalid = 0;
        s_axis_phase_tdata = '0;
        s_axis_cartesian_tdata = '0;
        
        file_err = $fopen("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/cordic_rot_errors.txt", "w");

        #20;
        rst = 0;
        #10;
        $display("=================================================");
        $display("   INICIANDO TESTBENCH MASIVO DEL CORDIC");
        $display("=================================================");

        // 2. Bucle para inyectar muestras
        for (int i = 0; i < NUM_SAMPLES_IN; i++) begin
            
            // Si el índice es múltiplo de 16, ES UN PILOTO -> Lo saltamos
            if (i % 16 != 0) begin
                
                @(posedge clk);
                
                // Es un dato. Extraemos P_in y Q_in
                p_in = memoria_in[i][15:0];
                q_in = memoria_in[i][31:16];
                
                // Extraemos la fase correspondiente para este dato
                phase_in = mem_fase_estimada[data_idx][17:0];
                
                // Inyectamos al CORDIC
                s_axis_phase_tvalid = 1'b1;
                s_axis_cartesian_tvalid = 1'b1;
                
                // NEGAMOS la fase usando la variable auxiliar
                neg_phase_in = -phase_in;
                s_axis_phase_tdata = { {6{neg_phase_in[17]}}, neg_phase_in };
                
                s_axis_cartesian_tdata = {
                    {8{q_in[15]}}, q_in,
                    {8{p_in[15]}}, p_in
                };
                
                data_idx++;
            end else begin
                // En el piloto, desactivamos valid para simular el comportamiento real
                @(posedge clk);
                s_axis_phase_tvalid = 0;
                s_axis_cartesian_tvalid = 0;
            end
        end

        // Dejamos de inyectar
        @(posedge clk);
        s_axis_phase_tvalid = 0;
        s_axis_cartesian_tvalid = 0;

        // Esperamos a que salgan todos los datos
        wait(out_idx == NUM_SAMPLES_OUT);
        #100;
        
        $display(" ");
        $display("=================================================");
        $display("               RESUMEN DE PRUEBA                 ");
        $display("=================================================");
        $display("  Muestras Inyectadas : %0d", data_idx);
        $display("  Muestras Revisadas  : %0d", out_idx);
        $display("  Errores Detectados  : %0d", error_counter);
        
        if (error_counter == 0) begin
            $display("  -> [ OK ] El CORDIC esta rotando a la perfeccion.");
        end else begin
            $display("  -> [FALLO] Revisa el log para ver donde y cuanto falla.");
        end
        $display("=================================================");
        
        if (file_err != 0) $fclose(file_err);
        
        $finish;
    end

endmodule
