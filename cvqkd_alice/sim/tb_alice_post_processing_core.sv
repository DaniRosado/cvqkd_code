`timescale 1ns / 1ps

// ============================================================================
// Módulo:       tb_alice_post_processing_core
// Proyecto:     CV-QKD Hardware Accelerator
// Descripción:  Testbench de integración a nivel de subsistema. Verifica la
//               interacción perfecta entre el motor MDR y el decodificador LDPC:
//               carga el síndrome de Bob, ejecuta MDR + LDPC y compara la clave
//               reconciliada con la de Bob bit a bit.
// ============================================================================

module tb_alice_post_processing_core();

    // =====================================================================
    // 1. PARÁMETROS GLOBALES Y SEÑALES
    // =====================================================================
    localparam int TOTAL_BLOCKS = 3264;
    localparam int CLK_PERIOD   = 10; // Frecuencia de 100 MHz

    // Reloj y Reset
    logic clk;
    logic rst_n;

    // Control del Procesador Virtual (El Testbench)
    logic start_mdr;
    logic start_ldpc;

    // Banderas de Estado del Subsistema
    logic mdr_done;
    logic ldpc_done;
    logic ldpc_success;
    logic [7:0] iter_count;

    // Buses de Memoria de Entrada
    logic         ram_x_en;
    logic [13:0]  ram_x_addr;
    logic [127:0] ram_x_data;
    logic [255:0] ram_m_data;
    logic [31:0]  ram_k_data;

    // Síndrome objetivo y lectura de la clave
    logic         target_syn_we;
    logic [5:0]   target_syn_addr;
    logic [383:0] target_syn_data;
    logic         key_read_en;
    logic [6:0]   key_read_addr;
    logic [383:0] key_read_data;

    // =====================================================================
    // 2. EMULACIÓN DE MEMORIAS EXTERNAS (DDR / BRAM del ARM)
    // =====================================================================
    logic [127:0] ram_x_mem [0:TOTAL_BLOCKS-1];
    logic [255:0] ram_m_mem [0:TOTAL_BLOCKS-1];
    logic [31:0]  ram_k_mem [0:TOTAL_BLOCKS-1];
    logic [383:0] syndrome_mem [0:45];   // Síndrome de Bob
    logic [383:0] key_bob_mem  [0:67];   // Clave de Bob (68 columnas de 384 bits)

    initial begin
        // Cargamos la "Verdad Absoluta" exportada desde MATLAB
        $readmemh("alice_mdr_inputs.txt",    ram_x_mem);
        $readmemh("expected_m_messages.txt", ram_m_mem); // Lo que llegó de Bob
        $readmemh("alice_k_dynamic.txt",     ram_k_mem);
        $readmemb("expected_syndrome.txt",   syndrome_mem);
        $readmemb("block_bits.txt",          key_bob_mem);

        $display("---------------------------------------------------");
        $display("[TB-CORE] Archivos de entrada cargados en memoria externa.");
        $display("---------------------------------------------------");
    end

    // Respuesta síncrona de las memorias simuladas (BRAM)
    always_ff @(posedge clk) begin
        if (ram_x_en) begin
            ram_x_data <= ram_x_mem[ram_x_addr];
            ram_m_data <= ram_m_mem[ram_x_addr];
            ram_k_data <= ram_k_mem[ram_x_addr];
        end else begin
            ram_x_data <= '0;
            ram_m_data <= '0;
            ram_k_data <= '0;
        end
    end

    // =====================================================================
    // 3. INSTANCIACIÓN DEL SUBSISTEMA DE ALICE (DUT)
    // =====================================================================
    alice_post_processing_core u_dut (
        .clk              (clk),
        .rst_n            (rst_n),

        // Interfaz de Control
        .start_mdr        (start_mdr),
        .start_ldpc       (start_ldpc),
        .mdr_done         (mdr_done),
        .ldpc_done        (ldpc_done),
        .ldpc_success     (ldpc_success),
        .iter_count       (iter_count),

        // Interfaz de Memoria
        .ram_x_en         (ram_x_en),
        .ram_x_addr       (ram_x_addr),
        .ram_x_data       (ram_x_data),
        .ram_m_data       (ram_m_data),
        .ram_k_data       (ram_k_data),

        // Síndrome objetivo y lectura de la clave
        .target_syn_we    (target_syn_we),
        .target_syn_addr  (target_syn_addr),
        .target_syn_data  (target_syn_data),
        .key_read_en      (key_read_en),
        .key_read_addr    (key_read_addr),
        .key_read_data    (key_read_data)
    );

    // =====================================================================
    // 4. GENERACIÓN DE RELOJ Y SECUENCIA DE ESTÍMULOS
    // =====================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    int   key_errors;
    int   iterations;
    logic converged;

    initial begin
        // --- 4.1 Inicialización ---
        rst_n      = 0;
        start_mdr  = 0;
        start_ldpc = 0;
        target_syn_we = 0; target_syn_addr = 0; target_syn_data = '0;
        key_read_en   = 0; key_read_addr   = 0;

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        // --- 4.1b Síndrome de Bob (46 filas) ---
        for (int r = 0; r < 46; r++) begin
            @(posedge clk);
            target_syn_we   <= 1'b1;
            target_syn_addr <= r;
            target_syn_data <= syndrome_mem[r];
        end
        @(posedge clk);
        target_syn_we <= 1'b0;
        @(negedge clk);  // Los start se dan en el flanco de bajada (sin carreras con el DUT)

        // --- 4.2 Fase 1: Extracción de LLRs (Reconciliación Multidimensional) ---
        $display("[TB-CORE] Iniciando Fase 1: Extracción de Información Cuántica (MDR)...");
        start_mdr = 1;
        @(negedge clk);
        start_mdr = 0;

        // Esperamos a que el Datapath purificado y la FSM procesen los 13056 bloques
        wait(mdr_done == 1'b1);
        $display("[TB-CORE] Fase 1 Completada. %0d Bloques procesados. L_BRAM llena.", TOTAL_BLOCKS);

        repeat (10) @(negedge clk); // Pausa realista simulando la latencia del procesador

        // --- 4.3 Fase 2: Corrección de Errores (Decodificación LDPC) ---
        $display("[TB-CORE] Iniciando Fase 2: Corrección de Errores (Decodificador LDPC)...");
        start_ldpc = 1;
        @(negedge clk);
        start_ldpc = 0;

        // Esperamos a que la matriz converja o se rinda tras el límite de iteraciones
        wait(ldpc_done == 1'b1);

        converged  = ldpc_success;  // Se capturan con ldpc_done (después vuelven a 0)
        iterations = iter_count;

        // --- 4.4 Comparación de la clave reconciliada con la de Bob ---
        key_errors = 0;
        for (int c = 0; c < 68; c++) begin
            @(posedge clk);
            key_read_en   <= 1'b1;
            key_read_addr <= c;
            @(posedge clk);
            key_read_en   <= 1'b0;
            #1;
            if (key_read_data !== key_bob_mem[c]) key_errors++;
        end

        // --- 4.5 Veredicto Final ---
        $display("---------------------------------------------------");
        if (converged) begin
            $display("  El LDPC ha convergido en %0d iteraciones. Columnas de clave distintas de Bob: %0d/68",
                     iterations, key_errors);
        end else begin
            $display("  [XXX] FALLO: El decodificador ha agotado las %0d iteraciones", iterations);
            $display("        sin alcanzar un síndrome válido. Clave descartada.");
        end
        if (converged && key_errors == 0) $display("RESULTADO: PASS");
        else                                 $display("RESULTADO: FAIL");
        $display("---------------------------------------------------");

        $finish;
    end

endmodule