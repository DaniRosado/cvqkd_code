`timescale 1ns / 1ps

module tb_mac_covariance();

    // Señales
    logic               clk;
    logic               rst;
    logic               clear;
    logic               enable;
    logic signed [15:0] data_bob;
    logic signed [15:0] data_alice;
    
    logic signed [63:0] sum_cov;
    logic signed [63:0] sum_val_bob;
    logic signed [63:0] sum_val_alice;

    // Instanciación del DUT
    mac_covariance dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(enable),
        .data_bob(data_bob),
        .data_alice(data_alice),
        .sum_cov(sum_cov),
        .sum_val_bob(sum_val_bob),
        .sum_val_alice(sum_val_alice)
    );

    // Reloj
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Prueba
    initial begin
        rst        = 1'b1;
        clear      = 1'b0;
        enable     = 1'b0;
        data_bob   = '0;
        data_alice = '0;
        
        #20;
        rst = 1'b0;
        
        $display("---------------------------------------------------");
        $display("[INFO] Iniciando Test de Covarianza Cruzada...");

        // INYECCIÓN PAR A PAR
        @(posedge clk);
        enable <= 1'b1; data_bob <=  16'sd2; data_alice <=  16'sd3;
        
        @(posedge clk);
        enable <= 1'b1; data_bob <= -16'sd3; data_alice <=  16'sd2;
        
        @(posedge clk);
        enable <= 1'b1; data_bob <=  16'sd4; data_alice <= -16'sd1;
        
        @(posedge clk);
        enable <= 1'b1; data_bob <= -16'sd5; data_alice <= -16'sd4;

        // Apagamos
        @(posedge clk);
        enable     <= 1'b0;
        data_bob   <= '0;
        data_alice <= '0;

        // Esperamos a que los multiplicadores y sumadores terminen
        repeat(5) @(posedge clk);

        // VERIFICACIÓN
        $display("[INFO] Sumatorio simple Bob esperado   : -2  | Obtenido: %0d", sum_val_bob);
        $display("[INFO] Sumatorio simple Alice esperado :  0  | Obtenido: %0d", sum_val_alice);
        $display("[INFO] Sumatorio Covarianza esperado   :  16 | Obtenido: %0d", sum_cov);

        if (sum_val_bob == -2 && sum_val_alice == 0 && sum_cov == 16) begin
            $display(" ");
            $display("  [ OK ] ¡CHECK DE COVARIANZA SUPERADO! ");
            $display("         Cruces de signos y sumas perfectas.");
            $display(" ");
        end else begin
            $display(" ");
            $display("  [ X ]  ¡ERROR EN LOS DSP Slices! ");
            $display(" ");
        end

        $display("---------------------------------------------------");
        $finish;
    end
endmodule