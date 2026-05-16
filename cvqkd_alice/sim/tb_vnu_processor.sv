`timescale 1ns / 1ps

module tb_vnu_processor;

    // =========================================================================
    // 1. Parámetros y Señales
    // =========================================================================
    parameter int W = 8;

    logic         clk;
    logic         rst_n;
    
    // Entradas al UUT
    logic [W-1:0] p_n_in;
    logic [W-1:0] r_old_in;
    logic [W-1:0] r_new_in;
    
    // Salidas del UUT
    logic [W-1:0] q_mn_out;
    logic [W-1:0] p_n_out;
    logic         hard_decision;

    // =========================================================================
    // 2. Instanciación del Unit Under Test (UUT)
    // =========================================================================
    vnu_processor #(
        .W(W)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .p_n_in(p_n_in),
        .r_old_in(r_old_in),
        .r_new_in(r_new_in),
        .q_mn_out(q_mn_out),
        .p_n_out(p_n_out),
        .hard_decision(hard_decision)
    );

    // =========================================================================
    // 3. Funciones auxiliares para el TB
    // =========================================================================
    // Función para convertir enteros de simulación a Signo-Magnitud hardware
    function automatic logic [W-1:0] int_to_sm(input int val);
        logic sign;
        logic [W-2:0] mag;
        
        if (val < 0) begin
            sign = 1'b1;
            mag  = -val;
        end else begin
            sign = 1'b0;
            mag  = val;
        end
        // Si nos pasamos de rango en el testbench, lo forzamos al límite
        if (mag > 127) mag = 127;
        
        return {sign, mag};
    endfunction

    // Tarea para inyectar estímulos y verificar
    task test_vnu(
        input int p_val, 
        input int rold_val, 
        input int rnew_val, 
        input int exp_q_val, 
        input int exp_p_val, 
        input logic exp_hd
    );
        logic [W-1:0] expected_q_sm;
        logic [W-1:0] expected_p_sm;
        begin
            // 1. Inyectamos los datos en Signo-Magnitud
            p_n_in   = int_to_sm(p_val);
            r_old_in = int_to_sm(rold_val);
            r_new_in = int_to_sm(rnew_val);
            
            // 2. Traducimos las expectativas a Signo-Magnitud
            expected_q_sm = int_to_sm(exp_q_val);
            expected_p_sm = int_to_sm(exp_p_val);

            // 3. Esperamos el tiempo de propagación combinacional
            #10;
            
            // 4. Verificamos salidas
            if (q_mn_out !== expected_q_sm || p_n_out !== expected_p_sm || hard_decision !== exp_hd) begin
                $display("[FAIL] Error aritmético detectado.");
                $display("       Entradas (Dec): P=%0d, R_old=%0d, R_new=%0d", p_val, rold_val, rnew_val);
                $display("       Esperado Q_mn : %h (SM) | Obtenido: %h", expected_q_sm, q_mn_out);
                $display("       Esperado P_n  : %h (SM) | Obtenido: %h", expected_p_sm, p_n_out);
                $display("       Esperado HD   : %b      | Obtenido: %b", exp_hd, hard_decision);
                $stop;
            end else begin
                $display("[OK] P=%0d, Rold=%0d, Rnew=%0d -> Q=%0d, Pnew=%0d | HD=%b", 
                         p_val, rold_val, rnew_val, exp_q_val, exp_p_val, exp_hd);
            end
        end
    endtask

    // =========================================================================
    // 4. Escenario de Prueba (Estímulos y Verificación)
    // =========================================================================
    initial begin
        $display("=================================================");
        $display(" Iniciando Verificación de VNU (Motor Aritmético)");
        $display("=================================================");

        clk   = 0;
        rst_n = 1;

        $display("\n--- CASO 1: Sumas y restas simples (Positivas) ---");
        // Q = 10 - 2 = 8
        // Pnew = 8 + 5 = 13
        // LLR es positivo -> Decisión 0
        test_vnu(.p_val(10), .rold_val(2), .rnew_val(5), .exp_q_val(8), .exp_p_val(13), .exp_hd(1'b0));

        $display("\n--- CASO 2: Cruzando el cero (Inversión de signo) ---");
        // Q = 2 - 5 = -3
        // Pnew = -3 + (-6) = -9
        // LLR es negativo -> Decisión 1
        test_vnu(.p_val(2), .rold_val(5), .rnew_val(-6), .exp_q_val(-3), .exp_p_val(-9), .exp_hd(1'b1));

        $display("\n--- CASO 3: Saturación Positiva Extrema ---");
        // Q = 120 - (-10) = 130 -> ¡Satura a 127!
        // Pnew = 127 + 20 = 147 -> ¡Satura a 127!
        test_vnu(.p_val(120), .rold_val(-10), .rnew_val(20), .exp_q_val(127), .exp_p_val(127), .exp_hd(1'b0));

        $display("\n--- CASO 4: Saturación Negativa Extrema ---");
        // Q = -120 - 15 = -135 -> ¡Satura a -127!
        // Pnew = -127 + (-10) = -137 -> ¡Satura a -127!
        test_vnu(.p_val(-120), .rold_val(15), .rnew_val(-10), .exp_q_val(-127), .exp_p_val(-127), .exp_hd(1'b1));

        $display("=================================================");
        $display(" SIMULACIÓN COMPLETADA SIN ERRORES               ");
        $display("=================================================");
        
        $finish;
    end

endmodule