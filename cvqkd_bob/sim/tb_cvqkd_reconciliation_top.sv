`timescale 1ns / 1ps

module tb_cvqkd_reconciliation_top();

    // =========================================================================
    // 1. PARÁMETROS DEL SISTEMA
    // =========================================================================
    localparam int BLOCKS_PER_FRAME = 3264; // Bloques de 8D por trama
    localparam int ROWS             = 46;

    logic clk;
    logic rst_n;
    
    // Entradas
    logic         router_valid;
    logic [31:0]  router_data;
    logic [7:0]   trng_data;
    
    // Salidas
    logic         mdr_valid;
    logic [255:0] mdr_m_out;
    logic         syndrome_done;
    logic [383:0] syndrome_out [0:45];

    // =========================================================================
    // 2. MEMORIAS (Plantillas de Oro de MATLAB)
    // =========================================================================
    logic [127:0] mem_Y_in    [0:BLOCKS_PER_FRAME-1];
    logic [7:0]   mem_trng_in [0:BLOCKS_PER_FRAME-1];
    logic [255:0] mem_m_exp   [0:BLOCKS_PER_FRAME-1];
    logic [383:0] mem_syn_exp [0:ROWS-1];

    // =========================================================================
    // 3. GENERACIÓN DE RELOJ (100 MHz)
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // 4. INSTANCIACIÓN DEL DUT (Top Level)
    // =========================================================================
    cvqkd_reconciliation_top dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .router_valid (router_valid),
        .router_data  (router_data),
        .trng_data    (trng_data),
        .mdr_valid    (mdr_valid),
        .mdr_m_out    (mdr_m_out),
        .syndrome_done(syndrome_done),
        .syndrome_out (syndrome_out)
    );

    // =========================================================================
    // 5A. AUTO-CHECKER: MDR (Mensajes Públicos en Streaming)
    // =========================================================================
    int mdr_check_idx = 0;
    int mdr_err_count = 0;
    logic signed [31:0] hw_m [0:7];
    logic signed [31:0] sw_m [0:7];
    int err_diff;

    always_ff @(posedge clk) begin
        if (rst_n && mdr_valid) begin
            int idx_mod = mdr_check_idx % BLOCKS_PER_FRAME; // Reusamos datos para la trama 2
            
            for (int i = 0; i < 8; i++) begin
                hw_m[i] = mdr_m_out[(i*32) +: 32];
                sw_m[i] = mem_m_exp[idx_mod][(i*32) +: 32];
                
                err_diff = hw_m[i] - sw_m[i];
                if (err_diff < 0) err_diff = -err_diff;
                
                if (err_diff > 15000) begin
                    if (mdr_err_count < 10) $display("  [MDR FAIL] Bloque %0d | Dim %0d | Obt: %08X", mdr_check_idx, i+1, hw_m[i]);
                    mdr_err_count++;
                end
            end
            mdr_check_idx++;
        end
    end

    // =========================================================================
    // 5B. AUTO-CHECKER: SÍNDROME LDPC (Por tramas completas)
    // =========================================================================
    int syn_frames_checked = 0;
    int syn_err_count      = 0;

    always_ff @(posedge clk) begin
        if (rst_n && syndrome_done) begin
            $display("[CHECKER] Matriz del Sindrome de la Trama %0d lista. Verificando...", syn_frames_checked + 1);
            
            for (int i = 0; i < ROWS; i++) begin
                if (syndrome_out[i] !== mem_syn_exp[i]) begin
                    syn_err_count++;
                end
            end
            
            if (syn_err_count == 0) $display("  [ OK ] Trama %0d: Matriz de Sindrome Perfecta.", syn_frames_checked + 1);
            else                    $display("  [FAIL] Trama %0d: %0d errores en Sindrome.", syn_frames_checked + 1, syn_err_count);
            
            syn_frames_checked++;
            syn_err_count = 0;
        end
    end

    int contador = 1;
    // vamos a actualizar el TRNG cada vez que veamos la señal de valid_data del MDR, para simular que el TRNG se actualiza con cada bloque procesado
    always_ff @(posedge clk) begin
        if (dut.accum_valid) begin
            trng_data <= mem_trng_in[contador];
            if(contador < 3263) contador++;
            else    contador = 0;            
        end
    end

    // =========================================================================
    // 6. HILO PRINCIPAL: EMULADOR DEL ROUTER
    // =========================================================================
    initial begin
        rst_n        = 0;
        router_valid = 0;
        router_data  = '0;
        trng_data    = '0;

        $display("=========================================================================");
        $display("[TB TOP] Cargando archivos de MATLAB...");
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_mdr_inputs.txt", mem_Y_in); 
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_random_bits.txt", mem_trng_in); 
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_m_messages.txt", mem_m_exp);
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_syndrome.txt", mem_syn_exp);
        
        trng_data <= mem_trng_in[0];
        
        #40 rst_n = 1; #40;

        $display("[TB TOP] Iniciando inyeccion de 2 tramas (Modo Router: 32 bits/ciclo)...");
        
        // Inyectamos 2 tramas seguidas
        for (int frame = 0; frame < 2; frame++) begin
            for (int i = 0; i < BLOCKS_PER_FRAME; i++) begin

                // El Router envía los 128 bits divididos en 4 ciclos de 32 bits
                for (int j = 0; j < 4; j++) begin
                    @(posedge clk);
                    router_valid <= 1'b1;
                    // Extraemos los trozos de 32 bits empezando por los menos significativos
                    router_data  <= mem_Y_in[i][(j*32) +: 32];
                end
                
                // Ruido de red: Pausa aleatoria entre envíos del Router
                if ($urandom_range(0, 100) < 20) begin
                    @(posedge clk);
                    router_valid <= 1'b0;
                end
            end
        end
        

        // Apagar el Router
        @(posedge clk);
        router_valid <= 1'b0;
        router_data  <= '0;

        $display("[TB TOP] Emision finalizada. Esperando resolucion del pipeline y del Ping-Pong...");
        
        // Esperamos a que los Auto-Checkers confirmen las 2 tramas
        wait(syn_frames_checked == 2);
        
        // Esperamos un poco más para asegurar que el pipeline MDR se vació del todo
        #200;

        $display("-------------------------------------------------------------------------");
        if (mdr_err_count == 0) $display("  [ OK ] MDR: Los 6528 mensajes inyectados cruzaron el pipeline con exito.");
        else                    $display("  [FAIL] MDR: Detectados %0d errores en pipeline.", mdr_err_count);
        $display("=========================================================================");
        
        $finish;
    end

endmodule