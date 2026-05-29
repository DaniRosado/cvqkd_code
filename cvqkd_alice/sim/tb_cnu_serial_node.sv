`timescale 1ns / 1ps

module tb_cnu_serial_node();

    // Señales
    logic       clk;
    logic       rst_n;
    logic       start_row;
    logic       valid_in;
    logic [6:0] col_idx_in;
    logic [7:0] L_q_in;
    
    logic [6:0] min1_out, min2_out, min1_col_out;
    logic       total_sign_out;

    // Instancia del DUT
    cnu_serial_node dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_row     (start_row),
        .valid_in      (valid_in),
        .col_idx_in    (col_idx_in),
        .L_q_in        (L_q_in),
        .min1_out      (min1_out),
        .min2_out      (min2_out),
        .min1_col_out  (min1_col_out),
        .total_sign_out(total_sign_out)
    );

    // Generación de Reloj
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Función auxiliar para crear Signo-Magnitud
    function logic [7:0] to_sm(input logic sign, input logic [6:0] mag);
        return {sign, mag};
    endfunction

    // Tarea para inyectar un dato
    task send_data(input logic [6:0] col, input logic sign, input logic [6:0] mag);
        @(posedge clk);
        valid_in   <= 1'b1;
        col_idx_in <= col;
        L_q_in     <= to_sm(sign, mag);
        start_row  <= 1'b0;
    endtask

    initial begin
        // Reset inicial
        rst_n      = 0;
        start_row  = 0;
        valid_in   = 0;
        col_idx_in = 0;
        L_q_in     = 0;
        
        #20 rst_n = 1;
        
        $display("=== INICIANDO TESTBENCH CNU (SERIAL) ===");
        
        // --- TEST 1: Simular una fila de 5 aristas ---
        // Vamos a inyectar estos valores (Signo, Magnitud):
        // Col 0: (+, 40)
        // Col 2: (-, 12)  <- Debería ser Min 1
        // Col 5: (+, 60)
        // Col 8: (-, 20)  <- Debería ser Min 2
        // Col 9: (+, 16)  <- Debería desplazar al Min 2
        //
        // Signo total esperado: (+) ^ (-) ^ (+) ^ (-) ^ (+) = (+) -> 0
        // Min1 sin escalar: 12. Escalo (12 - 3) = 9
        // Min2 sin escalar: 16. Escalo (16 - 4) = 12
        // Min1 Columna: 2
        
        @(posedge clk);
        start_row = 1'b1; // Reseteamos la fila
        
        // Inyectamos los 5 datos
        send_data(7'd0, 1'b0, 7'd40); 
        send_data(7'd2, 1'b1, 7'd12);
        send_data(7'd5, 1'b0, 7'd60);
        send_data(7'd8, 1'b1, 7'd20);
        send_data(7'd9, 1'b0, 7'd16);
        
        // Paramos de inyectar
        @(posedge clk);
        valid_in <= 1'b0;
        
        // Dejamos un ciclo para que la salida se estabilice visualmente
        @(posedge clk);
        
        $display("\n-- Resultados de la Fila 1 --");
        $display("Min1 Magnitud Esperada: 9  | Obtenida: %0d", min1_out);
        $display("Min2 Magnitud Esperada: 12 | Obtenida: %0d", min2_out);
        $display("Columna del Min1 Esp. : 2  | Obtenida: %0d", min1_col_out);
        $display("Signo Total Esperado  : 0  | Obtenido: %0b", total_sign_out);
        
        if (min1_out == 9 && min2_out == 12 && min1_col_out == 2 && total_sign_out == 0)
            $display("-> [OK] Test de Búsqueda y Escalado Superado.");
        else
            $display("-> [FAIL] Hubo errores en el cálculo.");

        $display("\n=== TESTBENCH FINALIZADO ===");
        $finish;
    end

endmodule