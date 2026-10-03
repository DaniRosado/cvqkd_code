`timescale 1ns / 1ps

module tb_phase_interpolator();

    // =========================================================================
    // 1. Declaración de Parámetros y Señales
    // =========================================================================
    localparam THETA_WIDTH = 18; // Formato Q3.15
    localparam NUM_PILOTS   = 1742;  // 27857 / 16 = 1741 tramas completas + 1 piloto final
    localparam NUM_DATA_OUT = 26115; // 15 datos por cada par de pilotos consecutivos

    logic clk;
    logic rst;
    
    // Entradas al DUT
    logic signed [THETA_WIDTH-1:0] theta_in;
    logic valid_in;

    // Salidas del DUT
    logic fifo_re;
    logic signed [THETA_WIDTH-1:0] cordic_theta;
    logic cordic_valid;

    // Memorias para los vectores de MATLAB
    logic [31:0] mem_pilotos [0:NUM_PILOTS-1];
    logic [31:0] mem_fase_estimada [0:NUM_DATA_OUT-1];

    // Contadores y variables de monitoreo
    integer data_count = 0;
    integer error_count = 0;
    integer max_error = 0;
    int fase_esperada;   // Q3.15 completo (MATLAB guarda la fase desenrollada en 32 bits)
    integer current_error;

    // =========================================================================
    // 2. Instanciación del DUT (Design Under Test)
    // =========================================================================
    phase_interpolator #(
        .THETA_WIDTH(THETA_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .theta_in(theta_in),
        .valid_in(valid_in),
        .fifo_re(fifo_re),
        .cordic_theta(cordic_theta),
        .cordic_valid(cordic_valid)
    );

    // =========================================================================
    // 3. Generación de Reloj (100 MHz)
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // 4. Proceso Monitor (Comprobador de Resultados)
    // =========================================================================
    // Diferencia entre dos ángulos Q3.15 reducida a [-pi, pi] (MATLAB guarda la fase
    // desenrollada y el hardware la envuelve: difieren en múltiplos de 2*pi)
    localparam int Q15_PI = 102944, Q15_TWO_PI = 205887;
    function automatic int angle_err(input int a, input int b);
        int d = a - b;
        while (d >  Q15_PI) d -= Q15_TWO_PI;
        while (d < -Q15_PI) d += Q15_TWO_PI;
        return (d < 0) ? -d : d;
    endfunction
    always_ff @(negedge clk) begin
        if (cordic_valid) begin
            if (data_count < NUM_DATA_OUT) begin
                // Extraemos el valor esperado
                fase_esperada = $signed(mem_fase_estimada[data_count]);
                
                // IMPORTANTE: El DUT niega el ángulo (-theta_raw). Le damos la vuelta para comparar.
                current_error = angle_err($signed(-cordic_theta), fase_esperada);

                // Actualizamos estadísticas
                if (current_error > max_error) max_error = current_error;

                // Si el error es mayor de 30 unidades, avisamos
                if (current_error > 30) begin
                    error_count++;
                    if (error_count <= 20) begin // Imprimimos solo los primeros 20 para no saturar
                        $display("[ERROR INTERPOLADOR] Dato %0d: Esperado=%d, DUT=%d, Diff=%0d",
                                  data_count, fase_esperada, $signed(-cordic_theta), current_error);
                    end
                end
                
                // Freno de Emergencia si el error es absurdo (desbordamiento)
                if (current_error > 5000) begin
                     $display("\n[FATAL] Desbordamiento brutal detectado en dato %0d. Parando simulacion.", data_count);
                     //$stop;
                end
                
            end
            data_count++;
        end
    end

    // =========================================================================
    // 5. Proceso Estímulos (Inyección de Pilotos)
    // =========================================================================
    initial begin
        $readmemh("fase_pilotos_raw.txt",    mem_pilotos);
        $readmemh("fase_estimada_datos.txt", mem_fase_estimada);

        // A) Reset del sistema
        rst = 1'b1;
        valid_in = 1'b0;
        theta_in = '0;
        #20;
        rst = 1'b0;
        #10;

        $display("--- INICIANDO TEST DEL INTERPOLADOR AISLADO ---");

        // B) Bucle de inyección: 1 Piloto cada 16 ciclos
        for (int i = 0; i < NUM_PILOTS; i++) begin
            @(posedge clk);
            valid_in <= 1'b1;
            theta_in <= mem_pilotos[i][17:0]; 
            
            @(posedge clk);
            valid_in <= 1'b0;

            // Simulamos los 15 ciclos en los que llegan los datos
            repeat(15) @(posedge clk);
        end

        // C) Damos un margen para que vacíe los últimos cálculos
        repeat(50) @(posedge clk);

        // D) Reporte Final
        $display("\n=================================================================");
        $display("                  REPORTE DE INTERPOLACIÓN AISLADA               ");
        $display("=================================================================");
        $display("    Datos comprobados    : %0d / %0d", data_count, NUM_DATA_OUT);
        $display("    Error máximo         : %0d unidades", max_error);
        $display("    Errores (>30 uds)    : %0d", error_count);
        
        if (error_count == 0 && data_count == NUM_DATA_OUT) begin
            $display("\n    [ OK ] El interpolador matematico es PERFECTO.");
            $display("RESULTADO: PASS");
        end else begin
            $display("\n    [ X ]  El interpolador acumula error matematico.");
            $display("RESULTADO: FAIL");
        end
        $display("=================================================================\n");
        $finish;
    end

endmodule