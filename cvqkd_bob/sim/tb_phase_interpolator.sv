`timescale 1ns / 1ps

module tb_phase_interpolator();

    // =========================================================================
    // 1. Declaración de Parámetros y Señales
    // =========================================================================
    localparam THETA_WIDTH = 18; // Formato Q3.15
    localparam NUM_PILOTS = 3483; // 55713 / 16 = 3482 tramas completas + 1 piloto final
    localparam NUM_DATA_OUT = 52224;

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
    logic [31:0] mem_pilotos [0:3500];
    logic [31:0] mem_fase_estimada [0:NUM_DATA_OUT-1];

    // Contadores y variables de monitoreo
    integer data_count = 0;
    integer error_count = 0;
    integer max_error = 0;
    logic signed [17:0] fase_esperada;
    integer current_error;
    integer file_out;

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
    initial begin
        file_out = $fopen("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/sim_interpolator_alone.txt", "w");
        if (file_out == 0) begin
            $display("ERROR: No se pudo abrir el archivo para escribir.");
        end
    end
    always_ff @(negedge clk) begin
        if (cordic_valid) begin
            if (data_count < NUM_DATA_OUT) begin
                // Extraemos el valor esperado
                fase_esperada = mem_fase_estimada[data_count][17:0];
                
                // IMPORTANTE: El DUT niega el ángulo (-theta_raw). Le damos la vuelta para comparar.
                current_error = $signed(-cordic_theta) - fase_esperada;
                if (current_error < 0) current_error = -current_error; // Valor absoluto

                // Actualizamos estadísticas
                if (current_error > max_error) max_error = current_error;

                // Guardar en archivo: [idx, fase_dut, fase_esperada]
                if (file_out != 0) begin
                    $fdisplay(file_out, "%0d %0d %0d", data_count, $signed(-cordic_theta), fase_esperada);
                end

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
        // Cargamos los archivos (Asegúrate de que la ruta sea la correcta para tu PC)
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/fase_pilotos_raw.txt", mem_pilotos);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/fase_estimada_datos.txt", mem_fase_estimada);

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
        end else begin
            $display("\n    [ X ]  El interpolador acumula error matematico.");
        end
        $display("=================================================================\n");
        if (file_out != 0) $fclose(file_out);
        $finish;
    end

endmodule