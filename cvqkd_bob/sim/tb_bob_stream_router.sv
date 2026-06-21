`timescale 1ns / 1ps

module tb_bob_stream_router();

    // =========================================================================
    // PARÁMETROS DEL SISTEMA
    // =========================================================================
    localparam ADC_WIDTH      = 16;
    localparam FIBER_SAMPLES  = 27857; // Tramas con pilotos incluidos
    localparam TOTAL_BOB_DATA = 26112; // Datos útiles por bloque
    localparam TEST_SAMPLES   = 13056; // Datos de sacrificio esperados

    logic clk, rst;

    // --- Entradas al DSP ---
    logic signed [ADC_WIDTH-1:0] p_in, q_in;
    logic                        valid_in;

    // --- Salidas del DSP (Cables internos) ---
    logic signed [ADC_WIDTH-1:0] dsp_p_out, dsp_q_out;
    logic                        dsp_valid_out;
    logic [31:0]                 dsp_data_packed;

    // --- Entradas al Router (Máscara) ---
    logic mask_valid;
    logic mask_bit;

    // --- Salidas del Router ---
    logic        router_valid_sac;
    logic [31:0] router_data_sac;
    logic        router_valid_key;
    logic [31:0] router_data_key;

    // =========================================================================
    // MEMORIAS PARA LEER LOS .TXT DE MATLAB
    // =========================================================================
    logic [31:0] mem_fiber [0:FIBER_SAMPLES-1];
    logic        mem_mask  [0:TOTAL_BOB_DATA-1];
    
    // Leemos la memoria gigante de Bob (52224) aunque solo usemos la mitad para un bloque
    logic [31:0] mem_bob_ideal [0:52223]; 
    
    // Array interno del Testbench para guardar la "Plantilla de Oro"
    logic [31:0] expected_sac_data [0:TEST_SAMPLES-1];

    // =========================================================================
    // GENERACIÓN DE RELOJ (100 MHz)
    // =========================================================================
    always #5 clk = ~clk;

    // =========================================================================
    // EMPAQUETADO
    // =========================================================================
    assign dsp_data_packed = {dsp_q_out, dsp_p_out};

    // =========================================================================
    // INSTANCIACIÓN DE LOS MÓDULOS BAJO PRUEBA (DUT)
    // =========================================================================
    cvqkd_bob_dsp_top #(
        .ADC_WIDTH(ADC_WIDTH),
        .DSP_WIDTH(18)
    ) dsp_inst (
        .clk(clk),
        .rst(rst),
        .p_in(p_in),
        .q_in(q_in),
        .valid_in(valid_in),
        .p_out(dsp_p_out),
        .q_out(dsp_q_out),
        .valid_out(dsp_valid_out)
    );

    bob_stream_router router_inst (
        .clk(clk),
        .rst(rst),
        .dsp_valid(dsp_valid_out),
        .dsp_data(dsp_data_packed),
        .mask_valid(mask_valid),
        .mask_bit(mask_bit),
        .valid_sac(router_valid_sac),
        .data_sac(router_data_sac),
        .valid_key(router_valid_key),
        .data_key(router_data_key)
    );

    // =========================================================================
    // AUTO-CHECKER INTELIGENTE: TOLERANCIA Y BÚSQUEDA DE DESFASE
    // =========================================================================
    int sac_count = 0;
    int key_count = 0;
    int err_count = 0;

    logic signed [15:0] fpga_p, fpga_q;
    logic signed [15:0] mat_p,  mat_q;
    int err_p, err_q;
    int match_offset;
    int search_range = 10; // Buscamos +/- 10 posiciones alrededor para cazar el desfase

    always_ff @(posedge clk) begin
        if (rst) begin
            sac_count <= 0;
            key_count <= 0;
            err_count <= 0;
        end else begin
            // 1. Contar datos de la Clave Privada
            if (router_valid_key) begin
                key_count <= key_count + 1;
            end
            
            // 2. Comprobar los datos de Sacrificio con Tolerancia
            if (router_valid_sac) begin
                // Desempaquetamos los 32 bits
                fpga_p = router_data_sac[15:0];
                fpga_q = router_data_sac[31:16];
                mat_p  = expected_sac_data[sac_count][15:0];
                mat_q  = expected_sac_data[sac_count][31:16];
                
                // Calculamos error absoluto
                err_p = fpga_p - mat_p;
                err_q = fpga_q - mat_q;
                if (err_p < 0) err_p = -err_p;
                if (err_q < 0) err_q = -err_q;
                
                // Si el error supera el umbral de redondeo del CORDIC (> 5)
                if (err_p > 5 || err_q > 5) begin
                    
                    // RADAR: Buscamos si el dato está desfasado en MATLAB
                    match_offset = -999;
                    for (int k = -search_range; k <= search_range; k++) begin
                        if ((sac_count + k) >= 0 && (sac_count + k) < TEST_SAMPLES) begin
                            int temp_p = expected_sac_data[sac_count + k][15:0];
                            int temp_q = expected_sac_data[sac_count + k][31:16];
                            
                            int te_p = fpga_p - temp_p;
                            int te_q = fpga_q - temp_q;
                            if (te_p < 0) te_p = -te_p;
                            if (te_q < 0) te_q = -te_q;
                            
                            if (te_p <= 5 && te_q <= 5) begin
                                match_offset = k; // ¡Encontramos a dónde se ha desplazado!
                                break;
                            end
                        end
                    end
                    
                    // Imprimir resultados (limitado a los 20 primeros para no saturar Vivado)
                    if (err_count < 20) begin 
                        if (match_offset != -999) begin
                            $display("  [SHIFT] Indice %0d desfasado. La FPGA escupe el dato de MATLAB del indice %0d (Desfase: %+0d).", 
                                     sac_count, sac_count + match_offset, match_offset);
                        end else begin
                            $display("  [ERROR] Indice %0d irreconocible. FPGA: Q=%0d, P=%0d | MATLAB: Q=%0d, P=%0d", 
                                     sac_count, fpga_q, fpga_p, mat_q, mat_p);
                        end
                    end
                    err_count <= err_count + 1;
                end
                
                sac_count <= sac_count + 1;
            end
        end
    end
    // =========================================================================
    // ESTÍMULOS DEL TESTBENCH
    // =========================================================================
    initial begin
        clk = 0; rst = 1; valid_in = 0; p_in = 0; q_in = 0;
        mask_valid = 0; mask_bit = 0;

        $display("=========================================================================");
        $display("[TB ROUTER] Iniciando prueba de aislamiento: DSP -> Mega-FIFO -> Router");
        
        // 1. Cargar Archivos
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_raw_adc.txt", mem_fiber);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/mask_bit.txt", mem_mask);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_ram.txt", mem_bob_ideal);
        
        // 2. Construir la "Plantilla de Oro" filtrando bob_ram.txt con la máscara
        // Esto imita lo que tu antiguo script de MATLAB hacía para generar las entradas del estimador.
        begin
            int idx = 0;
            for (int i = 0; i < TOTAL_BOB_DATA; i++) begin
                if (mem_mask[i] == 1'b1) begin
                    expected_sac_data[idx] = mem_bob_ideal[i];
                    idx++;
                end
            end
            $display("[TB ROUTER] Plantilla de oro generada. %0d muestras esperadas.", idx);
        end

        #40 rst = 0;
        #40;

        // 3. Fase de Recepción Óptica (Secuestramos el CORDIC)
        $display("[TB ROUTER] Inyectando datos crudos de fibra al DSP...");
        for (int i = 0; i < FIBER_SAMPLES; i++) begin
            @(posedge clk);
            valid_in = 1'b1;
            q_in     = mem_fiber[i][31:16];
            p_in     = mem_fiber[i][15:0];
        end

        // 4. Parche de vaciado (Flush)
        $display("[TB ROUTER] Vaciando tuberias internas del DSP...");
        for (int i = 0; i < 50; i++) begin
            @(posedge clk);
            valid_in = 1'b1;
            q_in     = 16'd0;
            p_in     = 16'd0;
        end
        @(posedge clk);
        valid_in = 1'b0;

        // Esperamos a que la Mega-FIFO del Router se trague todo (1000 ns de seguridad)
        #1000;

        // 5. Criba de Máscara (Generando el Streaming)
        $display("[TB ROUTER] Inyectando la mascara para activar el enrutamiento...");
        for (int i = 0; i < TOTAL_BOB_DATA; i++) begin
            @(posedge clk);
            mask_valid = 1'b1;
            mask_bit   = mem_mask[i];
            
            // Si quieres ver cómo estira y encoge la FIFO, descomenta esto para meter pausas aleatorias
            /*
            if ($urandom_range(0, 10) > 8) begin
                @(posedge clk);
                mask_valid = 0;
                @(posedge clk);
            end
            */
        end
        
        @(posedge clk);
        mask_valid = 0;

        // Esperamos unos ciclos para que los últimos datos atraviesen el pipeline del Router
        #100;

        // 6. Reporte Final
        $display("-------------------------------------------------------------------------");
        $display("   RESULTADOS DEL ENRUTAMIENTO");
        $display("-------------------------------------------------------------------------");
        $display("   - Datos totales enviados a Estimacion (Sacrificio): %0d", sac_count);
        $display("   - Datos totales enviados a Reconciliacion (Clave) : %0d", key_count);
        $display("   - Errores de coincidencia con la plantilla ideal  : %0d", err_count);
        $display("-------------------------------------------------------------------------");

        if (err_count == 0 && sac_count == TEST_SAMPLES && key_count == (TOTAL_BOB_DATA - TEST_SAMPLES)) begin
            $display("  [ OK ] ¡EXITO ABSOLUTO! El Router y el Filtro Antibasura funcionan a la perfeccion.");
        end else begin
            $display("  [ X ]  ¡FALLO! Revisa los indices o el vaciado de la Mega-FIFO.");
        end
        $display("=========================================================================");
        
        $finish;
    end

endmodule