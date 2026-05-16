`timescale 1ns / 1ps

module tb_ldpc_top_system;

    // 1. Parámetros y Señales
    parameter int W = 8;
    parameter int Z = 384;
    
    logic clk, rst_n, start;
    logic done, success;
    
    logic [Z*W-1:0] llr_in_bus;
    logic [383:0]   bob_syndrome_in [0:45];
    logic [Z-1:0]   key_bits_out;

    // Memorias de referencia del Testbench
    logic [Z*W-1:0] ram_llr_input [0:67];
    logic [Z-1:0]   ram_key_ref   [0:67];

    // Flag de archivo de referencia faltante
    int fd_key_ref;

    // 2. Instanciación del Top del Decodificador
    ldpc_decoder_top #(
        .W(W),
        .Z(Z),
        .MAX_ITER(20)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .success(success),
        .llr_in_bus(llr_in_bus),
        .bob_syndrome_in(bob_syndrome_in),
        .key_bits_out(key_bits_out)
    );

    // 3. Generación de Reloj (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // 4. Carga de datos desde archivos de MATLAB
    initial begin
        $display("[INFO] Cargando datos MATLAB de cvqkd_matlab/ ...");
        // NOTA: u_bits.txt contiene bits de clave decodificados (68x384 bits),
        // usados aquí como placeholder de LLRs. Para LLRs reales, cargar desde
        // alice_ram.txt (13056 lineas hex de 32 bits) u otro archivo generado
        // por MATLAB con el formato {signo[1b], magnitud[7b]} por VNU.
        // Formato esperado: 68 lineas de 3072 bits cada una (384 VNUs * 8 bits).
        $readmemb("../data/u_bits.txt", ram_llr_input);
        $readmemb("../data/expected_syndrome.txt", bob_syndrome_in); // Síndrome de Bob (46x384 bits)
        
        // Verificar si existe bob_key_ref.txt (puede no estar generado aún)
        fd_key_ref = $fopen("bob_key_ref.txt", "r");
        if (fd_key_ref == 0) begin
            $display("[WARNING] bob_key_ref.txt no encontrado. Se omitirá la verificación de clave.");
            $display("          Generar con MATLAB: tb_generador_master.m en cvqkd_matlab/");
            ram_key_ref = '{default: '0}; // Inicializar a cero para evitar X
        end else begin
            $fclose(fd_key_ref);
            $readmemb("bob_key_ref.txt", ram_key_ref);
            $display("[INFO] bob_key_ref.txt cargado correctamente.");
        end
    end

    // 5. Secuencia de Verificación
    int errores_bits = 0;
    
    initial begin
        $display("=================================================");
        $display(" INICIANDO TEST DE SISTEMA LDPC (CV-QKD)         ");
        $display("=================================================");
        
        // Reset inicial por ciclos
        rst_n = 0; start = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);
        
        // Carga inicial del primer valor LLR en el bus
        llr_in_bus = ram_llr_input[0];
        
        // Disparo del decodificador
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Ciclo de carga: la FSM itera por columnas 0..67 en ST_LOAD.
        // Alimentamos llr_in_bus con cada columna secuencialmente.
        for (int col = 1; col < 68; col++) begin
            @(posedge clk);
            llr_in_bus = ram_llr_input[col];
        end
        
        $display("[INFO] Carga de %0d columnas LLR completada. Decodificando...", 68);
        
        // Esperamos a que termine (por éxito o por límite de iteraciones)
        wait(done == 1'b1);
        
        if (success) begin
            $display("[OK] ¡El decodificador ha convergido!");
            $display("-------------------------------------------------");
            $display(" CLAVE RECONCILIADA (key_bits_out): %h ...", key_bits_out[63:0]);
            
            // Verificar contra referencia si está disponible
            if (fd_key_ref != 0) begin
                $display(" VALIDANDO CLAVE VS REFERENCIA (bob_key_ref.txt)");
                // Comparar key_bits_out con la primera entrada de referencia
                if (key_bits_out !== ram_key_ref[0]) begin
                    $display("[FAIL] La clave no coincide con la referencia.");
                    $display("       key_bits_out = %h", key_bits_out);
                    $display("       esperado     = %h", ram_key_ref[0]);
                    errores_bits = 1;
                end else begin
                    $display("[SUCCESS] ¡CLAVE RECUPERADA SIN ERRORES!");
                    $display("          La reconciliación ha sido perfecta.");
                end
            end else begin
                $display("[INFO] No hay archivo de referencia. Verificación estructural únicamente.");
                $display("       key_bits_out = %h (los primeros 64 bits)", key_bits_out);
            end
            
        end else begin
            $display("[FAIL] La trama no ha convergido en %0d iteraciones.", uut.MAX_ITER);
            $display("       Revisar la relación señal/ruido (SNR) en MATLAB.");
            $display("       key_bits_out parcial = %h", key_bits_out);
        end

        $display("=================================================");
        $finish;
    end

endmodule