`timescale 1ns / 1ps

// Test de mac_moments: dos tramas de muestras aleatorias de 16 bits (incluidos los
// extremos) con huecos en 'enable' y un 'clear' entre ellas. Las cuatro sumas se
// comparan con las calculadas en el testbench.
module tb_mac_moments();

    localparam int N = 2000;

    logic clk = 0;
    logic rst, clear, enable;
    logic signed [15:0] data_a, data_b;
    logic signed [63:0] sum_sq_b, sum_b, sum_ab, sum_a;

    mac_moments dut (
        .clk(clk), .rst(rst), .clear(clear), .enable(enable),
        .data_a(data_a), .data_b(data_b),
        .sum_sq_b(sum_sq_b), .sum_b(sum_b), .sum_ab(sum_ab), .sum_a(sum_a)
    );

    always #5 clk = ~clk;

    int errors = 0;
    longint ref_sq_b, ref_b, ref_ab, ref_a;

    task automatic run_frame(input int frame);
        ref_sq_b = 0; ref_b = 0; ref_ab = 0; ref_a = 0;
        @(negedge clk); clear = 1;
        @(negedge clk); clear = 0;
        for (int i = 0; i < N; i++) begin
            @(negedge clk);
            enable = ($urandom % 4) != 0;   // Huecos aleatorios entre muestras
            data_a = (i == 0) ? -16'sd32768 : $urandom;
            data_b = (i == 1) ? -16'sd32768 : $urandom;
            if (enable) begin
                ref_sq_b += longint'(data_b) * data_b;
                ref_b    += data_b;
                ref_ab   += longint'(data_a) * data_b;
                ref_a    += data_a;
            end
        end
        @(negedge clk); enable = 0;
        repeat (4) @(negedge clk);          // Vaciado de la tubería (3 ciclos)
        if (sum_sq_b != ref_sq_b || sum_b != ref_b || sum_ab != ref_ab || sum_a != ref_a) begin
            $display("  [FAIL] trama %0d: sum_sq_b=%0d (%0d) sum_b=%0d (%0d) sum_ab=%0d (%0d) sum_a=%0d (%0d)",
                     frame, sum_sq_b, ref_sq_b, sum_b, ref_b, sum_ab, ref_ab, sum_a, ref_a);
            errors++;
        end
    endtask

    initial begin
        rst = 1; clear = 0; enable = 0; data_a = 0; data_b = 0;
        repeat (3) @(negedge clk);
        rst = 0;
        run_frame(1);
        run_frame(2);   // El clear debe borrar la trama anterior
        if (errors == 0) $display("tb_mac_moments: 2 tramas correctas\nRESULTADO: PASS");
        else             $display("RESULTADO: FAIL");
        $finish;
    end

endmodule
