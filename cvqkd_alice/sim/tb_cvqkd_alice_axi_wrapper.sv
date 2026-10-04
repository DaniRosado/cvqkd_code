`timescale 1ns / 1ps

// ============================================================================
// Módulo:       tb_cvqkd_alice_axi_wrapper
// Proyecto:     CV-QKD Hardware Accelerator - Subsistema Alice
// Descripción:  Testbench de integración del wrapper AXI de Alice:
//               1. Carga la trama por AXI-Lite, como tools/alice_frames.py por
//                  JTAG: síndrome (0x100) y X, m y K por las ventanas de carga.
//                  Comprueba los contadores de bloques y el contenido de las BRAM.
//               2. Dispara MDR y decodificación LDPC por AXI-Lite.
//               3. Lee la clave reconciliada de 26.112 bits de la BRAM AXI-Lite.
//               4. Verifica coincidencia del 100% contra los bits de Bob.
// ============================================================================

module tb_cvqkd_alice_axi_wrapper();

    localparam int TOTAL_BLOCKS = 3264;
    localparam int CLK_PERIOD   = 10; // 100 MHz

    logic aclk;
    logic aresetn;

    // AXI-Lite
    logic [12:0] s_axi_awaddr;
    logic        s_axi_awvalid;
    wire         s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [3:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    wire         s_axi_wready;
    wire  [1:0]  s_axi_bresp;
    wire         s_axi_bvalid;
    logic        s_axi_bready;

    logic [12:0] s_axi_araddr;
    logic        s_axi_arvalid;
    wire         s_axi_arready;
    wire  [31:0] s_axi_rdata;
    wire  [1:0]  s_axi_rresp;
    wire         s_axi_rvalid;
    logic        s_axi_rready;

    // AXI-Stream X
    logic [31:0] s_axis_x_tdata;
    logic        s_axis_x_tvalid;
    wire         s_axis_x_tready;
    logic        s_axis_x_tlast;

    // AXI-Stream m
    logic [31:0] s_axis_m_tdata;
    logic        s_axis_m_tvalid;
    wire         s_axis_m_tready;
    logic        s_axis_m_tlast;

    // DUT
    cvqkd_alice_axi_wrapper #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(13),
        .TOTAL_BLOCKS(TOTAL_BLOCKS)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axis_x_tdata(s_axis_x_tdata),
        .s_axis_x_tvalid(s_axis_x_tvalid),
        .s_axis_x_tready(s_axis_x_tready),
        .s_axis_x_tlast(s_axis_x_tlast),
        .s_axis_m_tdata(s_axis_m_tdata),
        .s_axis_m_tvalid(s_axis_m_tvalid),
        .s_axis_m_tready(s_axis_m_tready),
        .s_axis_m_tlast(s_axis_m_tlast)
    );

    // Memorias de prueba cargadas desde MATLAB
    logic [127:0] mem_x_raw [0:TOTAL_BLOCKS-1];
    logic [255:0] mem_m_raw [0:TOTAL_BLOCKS-1];
    logic [31:0]  mem_k     [0:TOTAL_BLOCKS-1];
    logic [31:0]  mem_syn   [0:551];
    logic [383:0] mem_block_bits [0:67];

    initial begin
        $readmemh("alice_mdr_inputs.txt",        mem_x_raw);
        $readmemh("expected_m_messages.txt",     mem_m_raw);
        $readmemh("alice_k_dynamic.txt",         mem_k);
        $readmemh("expected_syndrome_words.hex", mem_syn);
        $readmemb("block_bits.txt",              mem_block_bits);
    end

    // Reloj
    initial begin
        aclk = 0;
        forever #(CLK_PERIOD/2) aclk = ~aclk;
    end

    // Tareas auxiliares AXI-Lite
    task axi_write(input [12:0] addr, input [31:0] data);
        @(posedge aclk);
        s_axi_awaddr  <= addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= 4'hF;
        s_axi_wvalid  <= 1'b1;
        s_axi_bready  <= 1'b1;

        wait(s_axi_awready && s_axi_wready);
        @(posedge aclk);
        s_axi_awvalid <= 1'b0;
        s_axi_wvalid  <= 1'b0;

        wait(s_axi_bvalid);
        @(posedge aclk);
        s_axi_bready  <= 1'b0;
    endtask

    task axi_read(input [12:0] addr, output [31:0] data);
        @(posedge aclk);
        s_axi_araddr  <= addr;
        s_axi_arvalid <= 1'b1;
        s_axi_rready  <= 1'b1;

        wait(s_axi_arready);
        @(posedge aclk);
        s_axi_arvalid <= 1'b0;

        wait(s_axi_rvalid);
        data = s_axi_rdata;
        @(posedge aclk);
        s_axi_rready  <= 1'b0;
    endtask

    // Secuencia de prueba
    logic [31:0] status_val;
    logic [31:0] cycles_val;
    logic [31:0] n_x, n_m, n_k;
    int load_errors = 0;
    int key_errors = 0;

    initial begin
        aresetn         = 0;
        s_axi_awaddr    = '0;
        s_axi_awvalid   = 0;
        s_axi_wdata     = '0;
        s_axi_wstrb     = '0;
        s_axi_wvalid    = 0;
        s_axi_bready    = 0;
        s_axi_araddr    = '0;
        s_axi_arvalid   = 0;
        s_axi_rready    = 0;
        s_axis_x_tdata  = '0;
        s_axis_x_tvalid = 0;
        s_axis_x_tlast  = 0;
        s_axis_m_tdata  = '0;
        s_axis_m_tvalid = 0;
        s_axis_m_tlast  = 0;

        #(CLK_PERIOD * 10);
        aresetn = 1;
        #(CLK_PERIOD * 10);

        $display("=========================================================================");
        $display("[TB-ALICE-AXI] TEST DE INTEGRACION DEL WRAPPER AXI4-LITE / AXI4-STREAM");
        $display("=========================================================================");

        // 1. Carga de la trama por AXI-Lite. Las BRAM ya traen la misma trama del
        //    bitstream: los contadores prueban que se han escrito todos los bloques y
        //    la comparación, que cada palabra ha ido a su sitio.
        $display("[CARGA] Sindrome, K, X y m por AXI-Lite (ventanas de carga)...");
        axi_write(13'h0000, 32'h00000001);   // Reset por software: contadores a 0
        axi_write(13'h0000, 32'h00000000);
        for (int i = 0; i < 552; i++)              axi_write(13'h0100 + i * 4, mem_syn[i]);
        for (int i = 0; i < TOTAL_BLOCKS; i++)     axi_write(13'h1E00 + (i % 128) * 4, mem_k[i]);
        for (int i = 0; i < TOTAL_BLOCKS * 4; i++) axi_write(13'h1800 + (i % 256) * 4, mem_x_raw[i / 4][(i % 4) * 32 +: 32]);
        for (int i = 0; i < TOTAL_BLOCKS * 8; i++) axi_write(13'h1C00 + (i % 128) * 4, mem_m_raw[i / 8][(i % 8) * 32 +: 32]);

        axi_read(13'h0010, n_x);
        axi_read(13'h0014, n_m);
        axi_read(13'h001C, n_k);
        for (int b = 0; b < TOTAL_BLOCKS; b++) begin
            if (dut.ram_x[b] !== mem_x_raw[b]) load_errors++;
            if (dut.ram_m[b] !== mem_m_raw[b]) load_errors++;
            if (dut.ram_k[b] !== mem_k[b])     load_errors++;
        end
        for (int i = 0; i < 552; i++) if (dut.syn_bram[i] !== mem_syn[i]) load_errors++;
        $display("  -> Bloques recibidos: X = %0d, m = %0d, K = %0d. Palabras distintas de MATLAB: %0d",
                 n_x, n_m, n_k, load_errors);
        if (n_x != TOTAL_BLOCKS || n_m != TOTAL_BLOCKS || n_k != TOTAL_BLOCKS || load_errors != 0) begin
            $display("[ERROR FATAL] La carga por AXI-Lite no ha dejado la trama en las BRAM.");
            $display("RESULTADO: FAIL");
            $finish;
        end

        #(CLK_PERIOD * 10);

        // 3. Disparo de Reconciliación con Auto-Run (MDR -> LDPC -> Extracción)
        $display("[CONFIG] Configurando registro de control AXI-Lite (Auto-Run MDR + LDPC)...");
        axi_write(13'h0000, 32'h0000000A); // bit 1: start_mdr, bit 3: auto_run

        $display("[PROCESO] Acelerador trabajando en hardware (MDR 8D + Decodificador LDPC)...");

        // Esperar a que el bit 'key_ready' (bit 3) se active en REG_STATUS
        status_val = 0;
        while ((status_val & 32'h00000008) == 0) begin
            axi_read(13'h0004, status_val);
            #(CLK_PERIOD * 50);
        end

        $display("\n=========================================================================");
        $display("[ESTADO] Proceso completado. REG_STATUS = 0x%08X", status_val);
        $display("  -> MDR Done      : %d", (status_val & 1));
        $display("  -> LDPC Done     : %d", ((status_val >> 1) & 1));
        $display("  -> LDPC Success  : %d", ((status_val >> 2) & 1));
        $display("  -> Clave Lista   : %d", ((status_val >> 3) & 1));
        axi_read(13'h0018, cycles_val);
        $display("  -> Latencia      : %0d ciclos (%0d iteraciones LDPC)", cycles_val, (status_val >> 8) & 8'hFF);

        if (((status_val >> 2) & 1) == 0 || cycles_val == 0) begin
            $display("[ERROR FATAL] El decodificador LDPC no convergio o el contador de ciclos no avanzo.");
            $display("RESULTADO: FAIL");
            $finish;
        end

        // 4. Lectura de la clave reconciliada por AXI-Lite y verificación contra MATLAB
        $display("\n[VERIFICACION] Leyendo clave reconciliada b_hat de la BRAM (0xA00 - 0x16BC)...");
        key_errors = 0;
        for (int col = 0; col < 68; col++) begin
            for (int w = 0; w < 12; w++) begin
                automatic int word_idx = col * 12 + w;
                automatic logic [31:0] expected_word = mem_block_bits[col][(w * 32) +: 32];
                automatic logic [31:0] read_word;

                axi_read(13'h0A00 + (word_idx * 4), read_word);

                if (read_word !== expected_word) begin
                    if (key_errors < 5) begin
                        $display("  [FAIL KEY] Palabra %0d (Col %0d, W %0d) | Leido: 0x%08X != Esperado: 0x%08X",
                                 word_idx, col, w, read_word, expected_word);
                    end
                    key_errors++;
                end
            end
        end

        $display("=========================================================================");
        if (key_errors == 0) begin
            $display("  [ OK ] !EXITO TOTAL! La clave de Alice reconciliada en hardware");
            $display("         coincide al 100%% bit a bit con Bob (816/816 palabras, 26.112 bits).");
            $display("RESULTADO: PASS");
        end else begin
            $display("  [FAIL] %0d palabras de clave con discrepancias.", key_errors);
            $display("RESULTADO: FAIL");
        end
        $display("=========================================================================\n");

        $finish;
    end

endmodule
