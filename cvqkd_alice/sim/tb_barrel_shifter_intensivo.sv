`timescale 1ns / 1ps

module tb_barrel_shifter_intensivo();

    localparam int Z = 384;
    localparam int W = 8;
    localparam int BUS_WIDTH = Z * W;
    
    // Arrays masivos para cargar los archivos de texto (Soportan hasta 4000 vectores)
    logic [BUS_WIDTH-1:0] mem_in     [0:3999];
    logic [BUS_WIDTH-1:0] mem_out    [0:3999];
    logic [8:0]           mem_shift  [0:3999];

    // Señales del Hardware (DUT)
    logic [W-1:0] data_in  [0:Z-1];
    logic [8:0]   shift_val;
    logic         dir_inverse;
    logic [W-1:0] data_out [0:Z-1];
    
    // Cables planos temporales
    logic [BUS_WIDTH-1:0] flat_in;
    logic [BUS_WIDTH-1:0] flat_expected;

    // Instancia del bloque que queremos torturar
    barrel_shifter #(.Z(Z), .W(W)) dut (
        .data_in    (data_in),
        .shift_val  (shift_val),
        .dir_inverse(dir_inverse),
        .data_out   (data_out)
    );
    
    int num_edges = 0;
    int errores_directo = 0;
    int errores_inverso = 0;

    initial begin
        $display("==================================================");
        $display("   TEST INTENSIVO DEL BARREL SHIFTER (Z=384)");
        $display("==================================================");
        
        // 1. Cargar las memorias desde los archivos
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/shifter_in.txt", mem_in);
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/shifter_out.txt", mem_out);
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/shifter_shift.txt", mem_shift);
        
        // Contar cuántos vectores reales se han cargado
        while (mem_shift[num_edges] !== 9'bx && num_edges < 4000) begin
            num_edges++;
        end
        $display("[INFO] Cargados %0d vectores de prueba desde MATLAB.", num_edges);
        
        // =======================================================
        // PRUEBA 1: RUTA DIRECTA (VNU -> CNU)
        // =======================================================
        $display("[TEST 1] Probando rotación directa (dir_inverse = 0)...");
        dir_inverse = 1'b0; 
        
        for (int i = 0; i < num_edges; i++) begin
            flat_in       = mem_in[i];
            flat_expected = mem_out[i];
            shift_val     = mem_shift[i];
            
            // Desempaquetar el bus plano hacia el hardware
            for (int z = 0; z < Z; z++) begin
                data_in[z] = flat_in[z*W +: W];
            end
            
            #10; // Dejar que la lógica combinacional asiente
            
            // Comprobación Bit a Bit
            for (int z = 0; z < Z; z++) begin
                if (data_out[z] !== flat_expected[z*W +: W]) begin
                    $display("[FALLO DIRECTO] Vector %0d, Shift %0d, Índice %0d", i, shift_val, z);
                    $display("  Esperado: %b", flat_expected[z*W +: W]);
                    $display("  Obtenido: %b", data_out[z]);
                    errores_directo++;
                end
            end
        end
        
        // =======================================================
        // PRUEBA 2: RUTA INVERSA (CNU -> VNU)
        // =======================================================
        $display("[TEST 2] Probando rotación inversa (dir_inverse = 1)...");
        dir_inverse = 1'b1; 
        
        for (int i = 0; i < num_edges; i++) begin
            // ¡Invertimos las entradas! Le damos el array rotado
            flat_in       = mem_out[i]; 
            // Esperamos que deshaga el camino hasta el original
            flat_expected = mem_in[i];  
            shift_val     = mem_shift[i];
            
            for (int z = 0; z < Z; z++) begin
                data_in[z] = flat_in[z*W +: W];
            end
            
            #10;
            
            for (int z = 0; z < Z; z++) begin
                if (data_out[z] !== flat_expected[z*W +: W]) begin
                    $display("[FALLO INVERSO] Vector %0d, Shift %0d, Índice %0d", i, shift_val, z);
                    errores_inverso++;
                end
            end
        end
        
        // =======================================================
        // PRUEBA AUTOMÁTICA AUTÓNOMA (384 Shifts x 2 Direcciones)
        // =======================================================
        $display("\n[TEST 3] Verificación Exhaustiva Autónoma (Todos los 384 desplazamientos con datos aleatorios)...");
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
        end else begin
            $display("   *** ALERTA ROJA: SE ENCONTRARON FALLOS ***");
            $display("   Errores Directos: %0d", errores_directo);
            $display("   Errores Inversos: %0d", errores_inverso);
        end
        $display("==================================================");
        $finish;
    end

endmodule