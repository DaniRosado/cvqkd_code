`timescale 1ns / 1ps

module tb_vnu_node();

    // Señales
    logic [7:0] L_read, R_old, L_q;
    logic [7:0] L_q_delayed, R_new, L_write;

    // Instancia del DUT
    vnu_node dut (
        .L_read      (L_read),
        .R_old       (R_old),
        .L_q         (L_q),
        .L_q_delayed (L_q_delayed),
        .R_new       (R_new),
        .L_write     (L_write)
    );

    // Tarea de ayuda para imprimir resultados en Signo-Magnitud
    task check_result(input string name, input logic [7:0] val, input int expected_val);
        int real_val;
        if (val[7]) real_val = -int'(val[6:0]);
        else        real_val =  int'(val[6:0]);
        
        if (real_val == expected_val)
            $display("[OK]   %s: Obtenido %d (Bin: %b)", name, real_val, val);
        else
            $display("[FAIL] %s: Esperado %d, Obtenido %d (Bin: %b)", name, expected_val, real_val, val);
    endtask

    // Tarea para convertir entero a SM en el TB
    function logic [7:0] to_sm(input int val);
        if (val < 0) return {1'b1, 7'(-val)};
        else         return {1'b0, 7'(val)};
    endfunction

    initial begin
        $display("=== INICIANDO TESTBENCH VNU ===");

        // --- TEST 1: Caso Normal ---
        $display("\n-- TEST 1: Resta y Suma Normal --");
        L_read = to_sm(20);  R_old = to_sm(5);  // L_q debe ser 15
        #10;
        check_result("L_q (20 - 5)", L_q, 15);
        
        L_q_delayed = L_q;   R_new = to_sm(-10); // L_write debe ser 5
        #10;
        check_result("L_write (15 + (-10))", L_write, 5);

        // --- TEST 2: Cruce por Cero ---
        $display("\n-- TEST 2: Cruce por Cero --");
        L_read = to_sm(-10); R_old = to_sm(20); // L_q debe ser -30
        #10;
        check_result("L_q (-10 - 20)", L_q, -30);
        
        L_q_delayed = L_q;   R_new = to_sm(40); // L_write debe ser 10
        #10;
        check_result("L_write (-30 + 40)", L_write, 10);

        // --- TEST 3: Saturación Positiva ---
        $display("\n-- TEST 3: Saturación Positiva --");
        L_read = to_sm(100); R_old = to_sm(-50); // 150 -> Satura a 127
        #10;
        check_result("L_q (100 - (-50))", L_q, 127);

        // --- TEST 4: Saturación Negativa ---
        $display("\n-- TEST 4: Saturación Negativa --");
        L_read = to_sm(-100); R_old = to_sm(50); // -150 -> Satura a -127
        #10;
        check_result("L_q (-100 - 50)", L_q, -127);

        $display("\n=== TESTBENCH FINALIZADO ===");
        $finish;
    end

endmodule