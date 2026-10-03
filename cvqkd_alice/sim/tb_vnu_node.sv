`timescale 1ns / 1ps

// Test del nodo de variable (VNU) en signo-magnitud: mensajes R y L_q de W = 8 bits
// y LLR a posteriori de WL = 10 bits.
//   Fase 1: L_q = L_read - R_old (exacto en L_q_full, saturado a +/-127 para la CNU)
//   Fase 2: L_write = L_q_full + R_new, saturado a +/-511
module tb_vnu_node();

    localparam int W  = 8;
    localparam int WL = 10;

    logic [WL-1:0]      L_read, L_write;
    logic [W-1:0]       R_old, R_new, L_q;
    logic signed [WL:0] L_q_full, L_q_full_delayed;

    vnu_node #(.W(W), .WL(WL)) dut (
        .L_read          (L_read),
        .R_old           (R_old),
        .L_q             (L_q),
        .L_q_full        (L_q_full),
        .L_q_full_delayed(L_q_full_delayed),
        .R_new           (R_new),
        .L_write         (L_write)
    );

    int errors = 0;

    // Entero -> signo-magnitud de WL y de W bits
    function automatic logic [WL-1:0] sm(input int val);
        return (val < 0) ? {1'b1, (WL-1)'(-val)} : {1'b0, (WL-1)'(val)};
    endfunction
    function automatic logic [W-1:0] sm8(input int val);
        return (val < 0) ? {1'b1, (W-1)'(-val)} : {1'b0, (W-1)'(val)};
    endfunction

    function automatic int to_int(input logic [WL-1:0] val, input int bits);
        int mag = val & ((1 << (bits-1)) - 1);
        return val[bits-1] ? -mag : mag;
    endfunction

    // Aplica un caso completo (las dos fases) y comprueba las tres salidas
    task automatic check(input int l_read, input int r_old, input int r_new,
                         input int exp_lq, input int exp_lq_full, input int exp_lwrite);
        L_read = sm(l_read);
        R_old  = sm8(r_old);
        #1;
        L_q_full_delayed = L_q_full;
        R_new  = sm8(r_new);
        #1;
        if (to_int(L_q, W) != exp_lq || L_q_full != exp_lq_full || to_int(L_write, WL) != exp_lwrite) begin
            $display("  [FAIL] L_read=%0d R_old=%0d R_new=%0d -> L_q=%0d L_q_full=%0d L_write=%0d (esperado %0d %0d %0d)",
                     l_read, r_old, r_new, to_int(L_q, W), L_q_full, to_int(L_write, WL),
                     exp_lq, exp_lq_full, exp_lwrite);
            errors++;
        end
    endtask

    initial begin
        //      L_read  R_old  R_new | L_q   L_q_full  L_write
        check(   20,     5,    -10,     15,     15,        5);  // Caso normal
        check(  -10,    20,     40,    -30,    -30,       10);  // Cruce por cero
        check(  300,   -50,    100,    127,    350,      450);  // L_q satura, el posterior no
        check( -500,    50,    -20,   -127,   -550,     -511);  // Saturación negativa del posterior
        check(  511,  -127,    127,    127,    638,      511);  // Extremos de rango

        if (errors == 0) $display("tb_vnu_node: 5 casos correctos\nRESULTADO: PASS");
        else             $display("tb_vnu_node: %0d casos con error\nRESULTADO: FAIL", errors);
        $finish;
    end

endmodule
