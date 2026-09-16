`timescale 1ns / 1ps

module tb_estparam_completo();

    // =========================================================================
    // PARÁMETROS DEL SISTEMA
    // =========================================================================
    localparam N_SAMPLES  = 26112/2; 
    localparam N_BOB_DATA = 52224/2;
    localparam N_FIBER    = 27857; // (3482 tramas * 16) + 1 piloto final
    
    logic clk;
    logic rst;

    // =========================================================================
    // 1. EMULACIÓN DEL FLUJO DEL ADC (Lectura de MATLAB)
    // =========================================================================
    logic [31:0] mem_adc [0:N_FIBER-1];
    logic [15:0] adc_q, adc_p;
    logic        adc_valid;
    integer      adc_ptr;

    // =========================================================================
    // 2. CABLES DE INTERCONEXIÓN: DSP -> MEMORIA RAM -> ESTIMADOR
    // =========================================================================
    
    // Cables DSP -> Ping-Pong BRAM (Bob)
    logic        dsp_data_valid; 
    logic [15:0] dsp_out_q, dsp_out_p;
    
    // Cables Ping-Pong BRAM -> Estimador
    logic        irq_buffer_ready;
    logic        irq_buffer_side;
    logic [16:0] bob_read_addr;
    logic [31:0] bob_read_data;

    // Cables de Alice (Puerto A para pre-carga TB, Puerto B para Estimador)
    logic        alice_we;
    logic [14:0] alice_wr_addr;
    logic [31:0] alice_wr_data;
    logic [14:0] alice_rd_addr;
    logic [31:0] alice_rd_data;
    
    // Punteros (A sustituir por el hardware real)
    logic [14:0] ptr_rd_addr;
    logic [15:0] ptr_rd_data;
    
    // Control de flujo On-the-fly
    logic [15:0] alice_items_avail;
    logic [15:0] bob_items_avail;
    
    // Interfaz generador -> ptr_ram
    logic mask_valid;
    logic mask_bit;
    logic [15:0] gen_ram_addr;
    logic        gen_read_en;
    logic        gen_done;

    logic [31:0] mem_expected[0:3]; 
    logic [31:0] calib_VarA;

    // =========================================================================
    // SEÑALES DEL ESTIMADOR (Salidas)
    // =========================================================================
    logic        est_done;
    logic [31:0] T_est, T_sqrt_est, sigma_sq_est, sigma_est;

    // =========================================================================
    // 3. INSTANCIACIÓN DEL HARDWARE
    // =========================================================================
    
    // 3.1. DSP de Bob (Des-rotación de Fase)
    cvqkd_bob_dsp_top #(
        .ADC_WIDTH(16), .DSP_WIDTH(18)
    ) dsp_inst (
        .clk(clk), .rst(rst),
        .p_in(adc_p), .q_in(adc_q), .valid_in(adc_valid),
        .p_out(dsp_out_p), .q_out(dsp_out_q), .valid_out(dsp_data_valid)
    );

    // 3.2. Memoria de Bob (Ping-Pong Buffer)
    ping_pong_bram #(
        .DATA_WIDTH(32), .BLOCK_SIZE(N_BOB_DATA), .ADDR_WIDTH(17)
    ) bob_ram_inst (
        .clk_wr(clk), .rst(rst),
        .p_in(dsp_out_p), .q_in(dsp_out_q), .valid_in(dsp_data_valid),
        
        .clk_rd(clk), .rd_addr(bob_read_addr), .rd_data(bob_read_data),
        
        .buffer_ready_irq(irq_buffer_ready), .buffer_to_read(irq_buffer_side)
    );

    // 3.3. Memoria de Alice (Buffer BRAM con control de flujo)
    alice_bram_buffer #(
        .DATA_WIDTH(32), .ADDR_WIDTH(15)
    ) alice_ram_inst (
        .clk_wr(clk), .rst_wr(rst),
        .we(alice_we), .wr_addr(alice_wr_addr), .wr_data(alice_wr_data),
        
        .clk_rd(clk), .rst_rd(rst),
        .rd_addr(alice_rd_addr), .rd_data(alice_rd_data),
        
        .items_avail(alice_items_avail)
    );

    // 3.4. Generador de Direcciones de Bob
    generador_direcciones_sacrificio #(
        .N_TOTAL_DATOS(N_BOB_DATA)
    ) gen_dir_inst (
        .clk(clk), .rst(rst),
        .mask_valid(mask_valid), .mask_bit(mask_bit),
        .ram_addr(gen_ram_addr), .read_en(gen_read_en), .done(gen_done)
    );

    // 3.5. Memoria de Punteros de Bob (ptr_ram_buffer)
    ptr_ram_buffer #(
        .DATA_WIDTH(16), .ADDR_WIDTH(15)
    ) ptr_ram_inst (
        .clk_wr(clk), .rst_wr(rst),
        .we(gen_read_en), .wr_data(gen_ram_addr),
        
        .clk_rd(clk), .rst_rd(rst),
        .rd_addr(ptr_rd_addr), .rd_data(ptr_rd_data),
        
        .items_avail(bob_items_avail)
    );

    logic est_start;
    logic est_side;
    // Este bloque emula lo que haría un controlador de interrupciones
    always_ff @(posedge clk) begin
        if (rst) begin
            est_start <= 1'b0;
            est_side  <= 1'b0;
        end else begin
            // Cuando la RAM avisa que un buffer está lleno... 
            if (irq_buffer_ready) begin
                est_start <= 1'b1;            // 1. Decimos al Estimador que empiece
                est_side  <= irq_buffer_side; // 2. Le decimos qué lado leer (Ping o Pong) [cite: 184]
            end else begin
                est_start <= 1'b0;            // Solo un pulso de inicio
            end
        end
    end
    
    // =========================================================================
    // INSTANCIA DEL TOP-LEVEL (Conexiones finales)
    // =========================================================================
    param_estimator_top #(.NUM_SAMPLES(N_SAMPLES)) estimator_inst (
        .clk(clk), .rst(rst),
        .start(est_start),        // <--- Conectado a la interrupción
        .ping_pong_bit(est_side), // <--- Conectado al selector de la RAM
        .done(est_done),
        
        .ptr_addr(ptr_rd_addr),   .ptr_data(ptr_rd_data),
        .bob_addr(bob_read_addr), .bob_data(bob_read_data),
        .alice_addr(alice_rd_addr), .alice_data(alice_rd_data),
        
        .alice_items_avail(alice_items_avail),
        .bob_items_avail(bob_items_avail),
        
        .calib_VarA(calib_VarA),
        
        .T_estimated(T_est), 
        .T_sqrt_estimated(T_sqrt_est),
        .sigma_sq_estimated(sigma_sq_est), 
        .sigma_estimated(sigma_est)
    );

    // =========================================================================
    // GENERADOR DE RELOJ Y ESTÍMULOS
    // =========================================================================
    initial begin
        clk = 0; forever #5 clk = ~clk;
    end

    // Memoria temporal para cargar Alice y la Máscara
    logic [31:0] mem_alice_file [0:N_SAMPLES-1];
    logic        mask_mem [0:N_BOB_DATA-1];

    initial begin
        // 1. Cargamos archivos de MATLAB
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/bob_raw_adc.txt", mem_adc);
        $readmemb("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/mask_bit.txt", mask_mem);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/alice_ram.txt", mem_alice_file);
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/expected_llr_math.txt", mem_expected);

        rst = 1; adc_valid = 0; adc_ptr = 0; calib_VarA = 32'd40000; alice_we = 0;
        adc_q = 0; adc_p = 0; mask_valid = 0; mask_bit = 0;
        #50 rst = 0;
        
        $display("\n=======================================================");
        $display("[INFO] Iniciando Simulacion Sistema End-to-End...");
        
        // 2. Simular carga de datos y máscara (On-the-fly concurrente)
        $display("[INFO] 1. Emulando la llegada progresiva de Alice y la Mascara de Bob...");
        
        fork
            // CPU cargando Alice lentamente
            begin
                for (int i=0; i<N_SAMPLES; i++) begin
                    @(posedge clk);
                    alice_we <= 1'b1;
                    alice_wr_addr <= i;
                    alice_wr_data <= mem_alice_file[i];
                    if ($random % 5 == 0) begin
                        @(posedge clk) alice_we <= 1'b0;
                        @(posedge clk);
                    end
                end
                @(posedge clk) alice_we <= 1'b0;
            end
            
            // Microcontrolador inyectando máscara al generador
            begin
                for (int i=0; i<N_BOB_DATA; i++) begin
                    @(posedge clk);
                    mask_valid <= 1'b1;
                    mask_bit <= mask_mem[i];
                    if ($random % 4 == 0) begin
                        @(posedge clk) mask_valid <= 1'b0;
                        @(posedge clk);
                    end
                end
                @(posedge clk) mask_valid <= 1'b0;
            end
        join_none

        // 3. Streaming de datos del ADC hacia el DSP
        $display("[INFO] 2. Inyectando %0d muestras de fibra al DSP...", N_FIBER);
        while (adc_ptr < N_FIBER) begin
            @(posedge clk);
            adc_valid <= 1'b1;
            {adc_q, adc_p} <= mem_adc[adc_ptr];
            adc_ptr++;
        end
        @(posedge clk) adc_valid <= 1'b0;

        // 4. Esperamos a que la FSM del estimador termine todo el proceso
        $display("[INFO] 3. DSP trabajando... Esperando interrupcion de memoria y calculo final...");
        wait(est_done == 1'b1);
        $display("[INFO] 4. Matematicas completadas. Verificando...\n");

        verificar_sistema();
        #100 $finish;
    end

    // =========================================================================
    // TAREA DE COMPROBACIÓN
    // =========================================================================
    task verificar_sistema();
        integer err[4], i;
        err[0] = $signed(T_est)        - $signed(mem_expected[0]);
        err[1] = $signed(T_sqrt_est)   - $signed(mem_expected[1]);
        err[2] = $signed(sigma_sq_est) - $signed(mem_expected[2]);
        err[3] = $signed(sigma_est)    - $signed(mem_expected[3]);

        for(i=0; i<4; i++) if(err[i] < 0) err[i] = -err[i];

        $display("-------------------------------------------------------------------------");
        $display("    PARAMETRO     | FPGA (Q16.16) | MATLAB (Ideal) | ERROR (Bits) ");
        $display("------------------+---------------+----------------+------------------");
        $display(" Ganancia T_est   |  %12d |   %12d |   %8d", T_est,        mem_expected[0], err[0]);
        $display(" Raiz Sqrt(T)     |  %12d |   %12d |   %8d", T_sqrt_est,   mem_expected[1], err[1]);
        $display(" Varianza Sigma^2 |  %12d |   %12d |   %8d", sigma_sq_est, mem_expected[2], err[2]);
        $display(" Desviacion Sigma |  %12d |   %12d |   %8d", sigma_est,    mem_expected[3], err[3]);
        $display("-------------------------------------------------------------------------");
        
        if (err[0] < 15 && err[1] < 15 && err[2] < 15 && err[3] < 15) begin
            $display("  [ OK ] ¡SISTEMA END-TO-END VERIFICADO CON EXITO! ");
            $display("         Desde el fotodiodo hasta el LDPC, el hardware es robusto.");
        end else begin
            $display("  [ X ]  ¡FALLO! Error detectado en la cadena de transmision.");
        end
        $display("=======================================================\n");
    endtask

endmodule