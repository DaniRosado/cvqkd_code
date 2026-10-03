`timescale 1ns / 1ps

// =============================================================================
// Testbench del wrapper AXI de Bob (trama completa con vectores de MATLAB)
//   Fase 1: reset -> carga de clave -> ADC -> máscara + Alice, con backpressure
//           aleatorio en las salidas MDR y síndrome. Comprueba MDR (3.264 beats,
//           TLAST solo en el último), síndrome (46 filas == MATLAB, TLAST en la 45)
//           y los bits de estado sticky (done_est, syndrome_done, key_ready, data_loss).
//   Fase 2: soft reset SIN recargar la clave -> no debe salir ningún mensaje MDR
//           y data_loss debe activarse (la clave usada no se reutiliza).
// Vuelca las salidas a dump.txt para compararlas bit a bit entre versiones.
// =============================================================================
module tb_cvqkd_bob_axi_wrapper();

    localparam int N_FIBER     = 27857; // Muestras ADC (datos + pilotos)
    localparam int N_MASK_BITS = 26112;
    localparam int N_ALICE     = 13056;
    localparam int N_BLOCKS    = 3264;  // Bloques MDR = bytes de clave
    localparam int ROWS        = 46;
    localparam int KEY_WORDS   = 816;

    localparam logic [11:0] REG_CTRL   = 12'h000;
    localparam logic [11:0] REG_CALIB  = 12'h004;
    localparam logic [11:0] REG_STATUS = 12'h008;
    localparam logic [11:0] REG_KEY    = 12'h100;

    logic aclk = 0, aresetn = 0;
    always #5 aclk = ~aclk;

    // --- AXI4-Lite ---
    logic [11:0] s_axi_awaddr = '0, s_axi_araddr = '0;
    logic [2:0]  s_axi_awprot = '0, s_axi_arprot = '0;
    logic        s_axi_awvalid = 0, s_axi_wvalid = 0, s_axi_arvalid = 0;
    logic        s_axi_bready = 1, s_axi_rready = 1;
    logic [31:0] s_axi_wdata = '0;
    logic [3:0]  s_axi_wstrb = 4'hF;
    logic        s_axi_awready, s_axi_wready, s_axi_bvalid, s_axi_arready, s_axi_rvalid;
    logic [1:0]  s_axi_bresp, s_axi_rresp;
    logic [31:0] s_axi_rdata;

    // --- AXI4-Stream de entrada ---
    logic [31:0] s_axis_pq_tdata = '0, s_axis_alice_tdata = '0, s_axis_mask_tdata = '0;
    logic        s_axis_pq_tvalid = 0, s_axis_alice_tvalid = 0, s_axis_mask_tvalid = 0;
    logic        s_axis_pq_tlast = 0, s_axis_alice_tlast = 0, s_axis_mask_tlast = 0;
    logic        s_axis_pq_tready, s_axis_alice_tready, s_axis_mask_tready;

    // --- AXI4-Stream de salida ---
    logic [255:0] m_axis_mdr_tdata;
    logic [511:0] m_axis_syndrome_tdata;
    logic         m_axis_mdr_tvalid, m_axis_mdr_tlast, m_axis_mdr_tready = 0;
    logic         m_axis_syndrome_tvalid, m_axis_syndrome_tlast, m_axis_syndrome_tready = 0;

    cvqkd_bob_axi_wrapper dut (.*);

    // =========================================================================
    // Vectores de MATLAB
    // =========================================================================
    logic [31:0]  mem_adc   [0:N_FIBER-1];
    logic         mem_mask  [0:N_MASK_BITS-1];
    logic [31:0]  mem_alice [0:N_ALICE-1];
    logic [7:0]   mem_key   [0:N_BLOCKS-1];
    logic [383:0] mem_syn   [0:ROWS-1];

    // =========================================================================
    // Tareas AXI4-Lite
    // =========================================================================
    task automatic axi_write(input logic [11:0] addr, input logic [31:0] data);
        s_axi_awaddr <= addr; s_axi_wdata <= data;
        s_axi_awvalid <= 1;   s_axi_wvalid <= 1;
        @(posedge aclk); while (!(s_axi_awready && s_axi_wready)) @(posedge aclk);
        s_axi_awvalid <= 0;   s_axi_wvalid <= 0;
        @(posedge aclk); while (!s_axi_bvalid) @(posedge aclk);
    endtask

    task automatic axi_read(input logic [11:0] addr, output logic [31:0] data);
        s_axi_araddr <= addr; s_axi_arvalid <= 1;
        @(posedge aclk); while (!s_axi_arready) @(posedge aclk);
        s_axi_arvalid <= 0;
        @(posedge aclk); while (!s_axi_rvalid) @(posedge aclk);
        data = s_axi_rdata;
    endtask

    task automatic soft_reset();
        axi_write(REG_CTRL, 32'd1);
        axi_write(REG_CTRL, 32'd2);
    endtask

    task automatic load_key();
        for (int w = 0; w < KEY_WORDS; w++)
            axi_write(REG_KEY + 12'(w * 4),
                      {mem_key[4*w+3], mem_key[4*w+2], mem_key[4*w+1], mem_key[4*w]});
    endtask

    // =========================================================================
    // Estímulos AXI4-Stream
    // =========================================================================
    task automatic send_adc(input int n);
        for (int i = 0; i < n; i++) begin
            s_axis_pq_tdata <= mem_adc[i]; s_axis_pq_tvalid <= 1;
            @(posedge aclk);
        end
        for (int i = 0; i < 80; i++) begin   // Relleno para cerrar la última trama del DSP
            s_axis_pq_tdata <= '0;
            @(posedge aclk);
        end
        s_axis_pq_tvalid <= 0;
    endtask

    task automatic send_mask(input int n_words);
        for (int w = 0; w < n_words; w++) begin
            for (int b = 0; b < 32; b++) s_axis_mask_tdata[b] <= mem_mask[32*w + b];
            s_axis_mask_tvalid <= 1;
            @(posedge aclk); while (!s_axis_mask_tready) @(posedge aclk);
        end
        s_axis_mask_tvalid <= 0;
    endtask

    task automatic send_alice();
        for (int i = 0; i < N_ALICE; i++) begin
            s_axis_alice_tdata <= mem_alice[i]; s_axis_alice_tvalid <= 1;
            @(posedge aclk); while (!s_axis_alice_tready) @(posedge aclk);
        end
        s_axis_alice_tvalid <= 0;
    endtask

    // =========================================================================
    // Consumidores con backpressure aleatorio + checkers
    // =========================================================================
    always_ff @(posedge aclk) begin
        m_axis_mdr_tready      <= ($urandom_range(0, 99) < 60);
        m_axis_syndrome_tready <= ($urandom_range(0, 99) < 30);
    end

    integer fd;
    int mdr_beats = 0, mdr_tlast_errors = 0;
    int syn_rows = 0, syn_errors = 0, syn_tlast_errors = 0;

    always_ff @(posedge aclk) begin
        if (m_axis_mdr_tvalid && m_axis_mdr_tready) begin
            $fdisplay(fd, "MDR %h", m_axis_mdr_tdata);
            if (m_axis_mdr_tlast != (mdr_beats == N_BLOCKS - 1)) mdr_tlast_errors++;
            mdr_beats++;
        end
        if (m_axis_syndrome_tvalid && m_axis_syndrome_tready) begin
            $fdisplay(fd, "SYN %h", m_axis_syndrome_tdata[383:0]);
            if (syn_rows < ROWS && m_axis_syndrome_tdata[383:0] !== mem_syn[syn_rows]) syn_errors++;
            if (m_axis_syndrome_tlast != (syn_rows == ROWS - 1)) syn_tlast_errors++;
            syn_rows++;
        end
        if (dut.done_est_pulse)
            $fdisplay(fd, "EST T=%h Tsq=%h s2=%h s=%h",
                      dut.T_final_out, dut.T_sqrt_out, dut.sigma_sq_out, dut.sigma_out);
    end

    // =========================================================================
    // Hilo principal
    // =========================================================================
    int errors = 0;
    int mdr_ref;
    logic [31:0] status;

    task automatic check(input bit cond, input string msg);
        if (cond) $display("  [ OK ] %s", msg);
        else begin $display("  [FAIL] %s", msg); errors++; end
    endtask

    initial begin
        $readmemh("bob_raw_adc.txt", mem_adc);
        $readmemb("mask_bit.txt", mem_mask);
        $readmemh("alice_ram.txt", mem_alice);
        $readmemb("bob_random_bits.txt", mem_key);
        $readmemb("expected_syndrome.txt", mem_syn);
        fd = $fopen("dump.txt", "w");  // Volcado de diagnóstico en el directorio de simulación

        repeat (10) @(posedge aclk);
        aresetn <= 1;
        repeat (5) @(posedge aclk);

        // ---------------------------------------------------------------------
        $display("[FASE 1] Trama completa con backpressure en las salidas");
        soft_reset();
        axi_write(REG_CALIB, 32'd50000);
        axi_read(REG_STATUS, status);
        check(status[2] == 1'b0, "key_ready = 0 antes de cargar la clave");
        load_key();
        axi_read(REG_STATUS, status);
        check(status[2] == 1'b1, "key_ready = 1 tras cargar la clave");

        send_adc(N_FIBER);
        repeat (200) @(posedge aclk);
        fork
            send_mask(N_MASK_BITS / 32);
            send_alice();
        join

        wait (syn_rows == ROWS && mdr_beats == N_BLOCKS);
        repeat (200) @(posedge aclk);
        axi_read(REG_STATUS, status);
        $fdisplay(fd, "END T=%h Tsq=%h s2=%h s=%h",
                  dut.T_final_out, dut.T_sqrt_out, dut.sigma_sq_out, dut.sigma_out);

        check(mdr_beats == N_BLOCKS && mdr_tlast_errors == 0, "MDR: 3264 beats y TLAST solo en el ultimo");
        check(syn_rows == ROWS && syn_errors == 0, "Sindrome: 46 filas identicas a MATLAB");
        check(syn_tlast_errors == 0, "Sindrome: TLAST solo en la fila 45");
        check(status[0] == 1'b1, "done_est se mantiene (sticky) y la CPU lo lee");
        check(status[1] == 1'b1, "syndrome_done = 1");
        check(status[2] == 1'b0, "key_ready = 0: clave consumida");
        check(status[3] == 1'b0, "data_loss = 0: no se perdio ningun dato");

        // ---------------------------------------------------------------------
        $display("[FASE 2] Soft reset sin recargar la clave");
        soft_reset();
        axi_read(REG_STATUS, status);
        check(status == 32'd0, "Estado limpio tras el soft reset (key_ready = 0)");
        mdr_ref = mdr_beats;
        send_adc(2000);
        repeat (200) @(posedge aclk);
        send_mask(20);
        repeat (500) @(posedge aclk);
        axi_read(REG_STATUS, status);
        check(mdr_beats == mdr_ref, "Sin clave no sale ningun mensaje MDR");
        check(status[3] == 1'b1, "data_loss = 1: muestras de clave descartadas por falta de clave");

        $fclose(fd);
        $display("=========================================================================");
        if (errors == 0) $display("  [ EXITO ] Todas las comprobaciones superadas.\nRESULTADO: PASS");
        else             $display("  [ FALLO ] %0d comprobaciones fallidas.\nRESULTADO: FAIL", errors);
        $display("=========================================================================");
        $finish;
    end

    // Watchdog
    initial begin
        #20ms;
        $display("[TIMEOUT] mdr_beats=%0d syn_rows=%0d", mdr_beats, syn_rows);
        $display("RESULTADO: FAIL");
        $finish;
    end

endmodule
