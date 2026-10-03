`timescale 1ns / 1ps

// Test exhaustivo del barrel shifter de Alice: los 384 desplazamientos en las dos
// direcciones con datos aleatorios, contra una rotación calculada en el testbench.
module tb_barrel_shifter();

    localparam int Z = 384;
    localparam int W = 8;

    // Señales del Hardware (DUT)
    logic [W-1:0] data_in  [0:Z-1];
    logic [8:0]   shift_val;
    logic         dir_inverse;
    logic [W-1:0] data_out [0:Z-1];

    // Instancia del bloque que queremos torturar
    barrel_shifter #(.Z(Z), .W(W)) dut (
        .data_in    (data_in),
        .shift_val  (shift_val),
        .dir_inverse(dir_inverse),
        .data_out   (data_out)
    );

    int errores_directo = 0;
    int errores_inverso = 0;

    initial begin
        $display("==================================================");
        $display("   TEST INTENSIVO DEL BARREL SHIFTER (Z=384)");
        $display("==================================================");

        // =======================================================
        // PRUEBA AUTOMÁTICA AUTÓNOMA (384 Shifts x 2 Direcciones)
        // =======================================================
        $display("[TEST] Verificación exhaustiva: los 384 desplazamientos en las dos direcciones...");
        begin
            int total_tests_auto = 0;
            logic [W-1:0] test_in [0:Z-1];
            logic [W-1:0] exp_out [0:Z-1];

            // Inicializar patrón aleatorio pero determinista
            for (int z = 0; z < Z; z++) begin
                test_in[z] = (z * 17 + 5) & 8'hFF;
            end

            // 3.1 Todos los shifts directos (0 a 383)
            dir_inverse = 1'b0;
            for (int s = 0; s < Z; s++) begin
                data_in   = test_in;
                shift_val = s[8:0];
                #10;
                for (int z = 0; z < Z; z++) begin
                    exp_out[(z + s) % Z] = test_in[z];
                end
                for (int z = 0; z < Z; z++) begin
                    if (data_out[z] !== exp_out[z]) begin
                        $display("[FALLO AUTO DIRECTO] Shift %0d, Pos %0d: Esperado %0d, Obtenido %0d",
                                 s, z, exp_out[z], data_out[z]);
                        errores_directo++;
                    end
                end
                total_tests_auto += Z;
            end

            // 3.2 Todos los shifts inversos (0 a 383)
            dir_inverse = 1'b1;
            for (int s = 0; s < Z; s++) begin
                data_in   = test_in;
                shift_val = s[8:0];
                #10;
                for (int z = 0; z < Z; z++) begin
                    exp_out[(z + (Z - (s % Z))) % Z] = test_in[z];
                end
                for (int z = 0; z < Z; z++) begin
                    if (data_out[z] !== exp_out[z]) begin
                        $display("[FALLO AUTO INVERSO] Shift %0d, Pos %0d: Esperado %0d, Obtenido %0d",
                                 s, z, exp_out[z], data_out[z]);
                        errores_inverso++;
                    end
                end
                total_tests_auto += Z;
            end
            $display("[INFO] Completados %0d chequeos individuales en modo autónomo.", total_tests_auto);
        end

        // =======================================================
        // VEREDICTO FINAL
        // =======================================================
        $display("==================================================");
        if (errores_directo == 0 && errores_inverso == 0) begin
            $display("   *** ÉXITO TOTAL: EL SHIFTER ES PERFECTO ***");
            $display("   Superados con éxito todos los tests individuales.");
            $display("RESULTADO: PASS");
        end else begin
            $display("   *** ALERTA ROJA: SE ENCONTRARON FALLOS ***");
            $display("   Errores Directos: %0d", errores_directo);
            $display("   Errores Inversos: %0d", errores_inverso);
            $display("RESULTADO: FAIL");
        end
        $display("==================================================");
        $finish;
    end

endmodule