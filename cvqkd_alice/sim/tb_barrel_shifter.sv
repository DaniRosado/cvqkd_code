`timescale 1ns / 1ps

module tb_barrel_shifter();

    // Reducimos Z a 8 solo para el testbench (facilita ver las formas de onda)
    localparam int Z = 8;
    localparam int W = 8;

    // Señales
    logic [W-1:0] data_in  [0:Z-1];
    logic [8:0]   shift_val;
    logic         dir_inverse;
    logic [W-1:0] data_out [0:Z-1];

    // Instancia del DUT (Device Under Test)
    barrel_shifter #(
        .Z(Z),
        .W(W)
    ) dut (
        .data_in    (data_in),
        .shift_val  (shift_val),
        .dir_inverse(dir_inverse),
        .data_out   (data_out)
    );

    initial begin
        $display("=== INICIANDO TESTBENCH BARREL SHIFTER ===");

        // 1. Inicializar la entrada con un patrón reconocible (ej. 10, 20, 30...)
        for (int i = 0; i < Z; i++) begin
            data_in[i] = (i + 1) * 10;
        end

        // --- TEST 1: Sin desplazamiento (Directo) ---
        shift_val   = 0;
        dir_inverse = 1'b0;
        #10;
        $display("TEST 1 (Shift 0, Directo) -> Out[0]: %0d (Esperado: 10)", data_out[0]);

        // --- TEST 2: Desplazamiento de 2 posiciones (Directo) ---
        // data_in[0] (que es 10) debería ir a data_out[2]
        shift_val   = 2;
        dir_inverse = 1'b0;
        #10;
        $display("TEST 2 (Shift 2, Directo) -> Out[2]: %0d (Esperado: 10)", data_out[2]);
        $display("TEST 2 (Shift 2, Directo) -> Out[0]: %0d (Esperado: 70)", data_out[0]); // El 70 da la vuelta

        // --- TEST 3: Desplazamiento de 2 posiciones (Inverso) ---
        // Para deshacer el camino, data_in[2] debería volver a data_out[0]
        // (Simulamos que la salida del test 2 entra al shifter inverso)
        data_in = data_out; // Metemos la salida rotada como nueva entrada
        shift_val   = 2;
        dir_inverse = 1'b1; // Modo Inverso
        #10;
        $display("TEST 3 (Shift 2, Inverso) -> Out[0]: %0d (Esperado: 10)", data_out[0]);

        $display("=== TESTBENCH FINALIZADO ===");
        $finish;
    end

endmodule