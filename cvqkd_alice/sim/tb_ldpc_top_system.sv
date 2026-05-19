`timescale 1ns / 1ps

module tb_ldpc_top_system;

    parameter int W = 16;
    parameter int Z = 384;

    logic clk, rst_n, start;
    logic done, success;
    
    logic [Z*W-1:0] llr_in_bus;
    logic [383:0]   bob_syndrome_in [0:45];
    logic [Z*W-1:0] ram_llr_input [0:67];
    logic [Z-1:0]   ram_key_ref   [0:67];

    int fd_key_ref, fd_u, fd_syn;

    wire  [Z-1:0] key_bits_out;

    ldpc_decoder_top #(
        .W(W), .Z(Z), .MAX_ITER(20)
    ) uut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .done(done), .success(success),
        .llr_in_bus(llr_in_bus),
        .bob_syndrome_in(bob_syndrome_in),
        .key_bits_out(key_bits_out),
        .debug_rd_addr(7'b0),
        .debug_rd_data()
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("=================================================");
        $display(" INICIANDO TEST DE SISTEMA LDPC (CV-QKD)");
        $display("=================================================");
        
        $display("[INFO] Cargando LLRs desde MATLAB...");
        fd_u = $fopen("C:/Users/usser/TFG/cvqkd_code/cvqkd_alice/sim/u_bits.txt", "r");
        if (fd_u == 0) fd_u = $fopen("sim/u_bits.txt", "r");
        if (fd_u == 0) fd_u = $fopen("../data/u_bits.txt", "r");
        if (fd_u == 0) begin
            $display("[FATAL] u_bits.txt no encontrado!");
            $finish;
        end
        for (int col = 0; col < 68; col++) begin
            logic [0:(Z*8)-1] line_bits;
            int code = $fscanf(fd_u, "%b\n", line_bits);
            for (int v = 0; v < Z; v++) begin
                bit sm_sign = line_bits[v*8 + 0];
                bit [6:0] sm_mag;
                for (int b = 1; b < 8; b++) sm_mag[7-b] = line_bits[v*8 + b];
                ram_llr_input[col][v*W +: W] = {sm_sign, {(W-1-7){1'b0}}, sm_mag};
            end
        end
        $fclose(fd_u);

        $display("[INFO] Cargando Clave Esperada (Bob)...");
        fd_key_ref = $fopen("C:/Users/usser/TFG/cvqkd_code/cvqkd_alice/sim/bob_key_ref.txt", "r");
        if (fd_key_ref == 0) fd_key_ref = $fopen("sim/bob_key_ref.txt", "r");
        if (fd_key_ref == 0) fd_key_ref = $fopen("../data/bob_key_ref.txt", "r");
        for (int col = 0; col < 68; col++) begin
            logic [0:Z-1] kb;
            int code = $fscanf(fd_key_ref, "%b\n", kb);
            for (int v = 0; v < Z; v++) ram_key_ref[col][v] = kb[v];
        end
        $fclose(fd_key_ref);

        $display("[INFO] Cargando Síndrome de Bob...");
        fd_syn = $fopen("C:/Users/usser/TFG/cvqkd_code/cvqkd_alice/sim/expected_syndrome.txt", "r");
        if (fd_syn == 0) fd_syn = $fopen("sim/expected_syndrome.txt", "r");
        if (fd_syn == 0) fd_syn = $fopen("../data/expected_syndrome.txt", "r");
        for (int row = 0; row < 46; row++) begin
            logic [0:Z-1] syn_bits;
            int code = $fscanf(fd_syn, "%b\n", syn_bits);
            for (int v=0; v<Z; v++) bob_syndrome_in[row][v] = syn_bits[v];
        end
        $fclose(fd_syn);

        // Reset inicial
        rst_n = 0; start = 0;
        #100;
        rst_n = 1;
        #20;
        
        // Disparo
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Alimentar bus de LLRs simulando la llegada desde el receptor
        for (int col = 0; col < 68; col++) begin
            llr_in_bus = ram_llr_input[col];
            @(posedge clk);
        end
        
        $display("[INFO] Decodificador en marcha. Esperando convergencia...");
        
        wait(done == 1'b1);
        
        if (success) begin
            $display("=================================================");
            $display("[SUCCESS] ¡CLAVE RECUPERADA SIN ERRORES!");
            $display("          La reconciliación ha convergido en %0d iteraciones.", uut.iter_cnt);
            $display("=================================================");
        end else begin
            $display("=================================================");
            $display("[FAIL] La trama no ha convergido en %0d iteraciones.", uut.iter_cnt);
            $display("=================================================");
        end
        $finish;
    end

    // Monitorización Analítica: Contar errores en cada paso por ST_CHECK (Estado 6)
    always @(posedge clk) begin
        if (uut.state == 3'd6) begin 
            int err_count = 0;
            for (int i = 0; i < 68; i++) begin
                for (int j = 0; j < Z; j++) begin
                    // Comparar el bit de signo de P (Decision Dura) con la referencia
                    if (uut.p_mem.ram[i][j*W + (W-1)] !== ram_key_ref[i][j]) begin
                        err_count++;
                    end
                end
            end
            $display("[ITER %0d] Símbolos erróneos respecto a la clave original: %0d / 26112", uut.iter_cnt, err_count);
        end
    end

endmodule