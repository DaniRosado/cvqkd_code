`timescale 1ns / 1ps

module tb_param_estimator_top();

    // =========================================================================
    // PARÁMETROS Y SEÑALES
    // =========================================================================
    localparam TEST_SAMPLES = 26112/2;
    localparam NUM_BOB_RAM  = 52224;
    
    logic clk, rst_n, start, done;
    
    // --- SEÑALES DE STREAMING ---
    logic        bob_stream_valid;
    logic [31:0] bob_stream_data;
    logic        alice_stream_valid;
    logic [31:0] alice_stream_data;
    
    // --- INTERFAZ AXI4-LITE (CPU ARM) ---
    logic signed [31:0] calib_VarA;
    
    logic signed [31:0] T_final_out;
    logic signed [31:0] sigma_sq_out;
    logic signed [31:0] sigma_out;
    logic [31:0]        num_samples_out;
    
    // --- SALIDAS GLOBALES ---
    logic signed [31:0] T_sqrt_out;

    // =========================================================================
    // ARRAYS DE MEMORIA (Lectura de archivos de MATLAB)
    // =========================================================================
    logic [15:0] mem_ptr    [0:TEST_SAMPLES-1];
    logic [31:0] mem_bob    [0:NUM_BOB_RAM-1]; 
    logic [31:0] mem_alice  [0:TEST_SAMPLES-1];
    logic [31:0] mem_expected [0:3];

    // =========================================================================
    // GENERACIÓN DE RELOJ (100 MHz)
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // INSTANCIACIÓN DEL DUT 
    // =========================================================================
    param_estimator_top #(
        .NUM_SAMPLES(TEST_SAMPLES)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        
        .bob_stream_valid(bob_stream_valid),
        .bob_stream_data(bob_stream_data),
        .alice_stream_valid(alice_stream_valid),
        .alice_stream_data(alice_stream_data),
        
        // Interfaz AXI (CPU -> HW)
        .calib_VarA(calib_VarA),
        
        // Interfaz AXI (HW -> CPU)
        .T_final_out(T_final_out),
        .sigma_sq_out(sigma_sq_out),
        .sigma_out(sigma_out),
        .num_samples_out(num_samples_out),
        
        // Salidas Hardware Globales
        .T_sqrt_out(T_sqrt_out)
    );

    // =========================================================================
    // PROCEDIMIENTO DE TEST (ESTÍMULOS)
    // =========================================================================
    initial begin
        rst_n = 0;
        start = 0;
        bob_stream_valid   = 0;
        alice_stream_valid = 0;
        bob_stream_data    = 0;
        alice_stream_data  = 0;
        calib_VarA = 32'd40000;

        $display("-------------------------------------------------------------------------");
        $display("[TB] Cargando archivos generados por MATLAB...");
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/ptr_ram.txt", mem_ptr);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/bob_ram.txt", mem_bob);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/alice_ram.txt", mem_alice);
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_llr_math.txt", mem_expected);
        $display("[TB] Archivos cargados con exito.");

        #20 rst_n = 1;
        #20;

        $display("[TB] Mandando pulso de START al estimador...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        @(posedge clk);

        $display("[TB] Inyectando las %0d muestras en Streaming...", TEST_SAMPLES);
        for (int i = 0; i < TEST_SAMPLES; i++) begin
            int ptr_sacrificio = mem_ptr[i];
            bob_stream_data   = mem_bob[ptr_sacrificio];
            alice_stream_data = mem_alice[i];
            
            bob_stream_valid   = 1;
            alice_stream_valid = 1;
            
            @(posedge clk);
            if ($urandom_range(0, 10) > 8) begin
                bob_stream_valid   = 0;
                alice_stream_valid = 0;
                @(posedge clk);
                @(posedge clk);
            end
        end
        
        bob_stream_valid   = 0;
        alice_stream_valid = 0;
        $display("[TB] Inyeccion terminada. Esperando resolucion del HW y SW...");

        wait(done == 1'b1);
        @(posedge clk);
        
        // 7. COMPROBACIÓN FINAL
        begin
            integer err [4];
            integer i;
            
            err[0] = T_final_out  - mem_expected[0];
            err[1] = T_sqrt_out   - mem_expected[1];
            err[2] = sigma_sq_out - mem_expected[2];
            err[3] = sigma_out    - mem_expected[3];

            for(i=0; i<4; i++) if(err[i] < 0) err[i] = -err[i];

            $display("-------------------------------------------------------------------------");
            $display("    PARAMETRO     | FPGA (Q16.16) | MATLAB (Ideal) | ERROR (Bits) ");
            $display("------------------+---------------+----------------+------------------");
            $display(" Ganancia T_est   |  %12d |   %12d |   %8d", T_final_out,  mem_expected[0], err[0]);
            $display(" T_sqrt           |  %12d |   %12d |   %8d", T_sqrt_out,   mem_expected[1], err[1]);
            $display(" Varianza Sigma^2 |  %12d |   %12d |   %8d", sigma_sq_out, mem_expected[2], err[2]);
            $display(" Desviacion Sigma |  %12d |   %12d |   %8d", sigma_out,    mem_expected[3], err[3]);
            $display("-------------------------------------------------------------------------");
            
            if (err[0]<=5 && err[1]<=5 && err[2]<=5 && err[3]<=5) begin
                $display("  [ OK ] ¡EXITO! El hardware emula a MATLAB con precision perfecta.");
            end else begin
                $display("  [ X ]  ¡FALLO! Error detectado en la cadena matematica.");
            end
            $display("=========================================================================");
        end
        
        $finish;
    end

endmodule