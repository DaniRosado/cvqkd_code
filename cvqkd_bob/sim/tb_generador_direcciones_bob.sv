`timescale 1ns / 1ps

module tb_generador_direcciones_bob();

    parameter N_TOTAL_DATOS = 52224;
    parameter N_SAMPLES     = 26112;

    // Entradas
    logic clk;
    logic rst;
    logic mask_valid;
    logic mask_bit;

    // Salidas
    logic [15:0] ram_addr;
    logic        read_en;
    logic        done;

    // Instanciación del módulo bajo prueba
    generador_direcciones_sacrificio #(
        .N_TOTAL_DATOS(N_TOTAL_DATOS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .mask_valid(mask_valid),
        .mask_bit(mask_bit),
        .ram_addr(ram_addr),
        .read_en(read_en),
        .done(done)
    );

    // Reloj
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // Periodo de 10ns
    end

    // Memoria para leer los archivos de estímulo
    logic mask_mem [0:N_TOTAL_DATOS-1];
    logic [15:0] ptr_mem [0:N_SAMPLES-1];
    
    string mask_file = "C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/mask_bit.txt";
    string ptr_file  = "C:/Users/usser/Vivado_Sources/cvqkd_bob/Matlab/ptr_ram.txt";

    // Variables de control y verificación
    int i_mask;
    int i_ptr;
    int errores;
    logic [15:0] current_ptr;

    // Proceso principal de estímulos
    initial begin
        // Inicialización
        rst = 1;
        mask_valid = 0;
        mask_bit = 0;
        i_mask = 0;
        i_ptr = 0;
        errores = 0;

        // Cargar archivos
        $readmemb(mask_file, mask_mem);
        $readmemh(ptr_file, ptr_mem);

        #50;
        rst = 0;
        #20;

        $display("Iniciando inyeccion de mascara...");

        // Inyectar bits de la máscara
        for (i_mask = 0; i_mask < N_TOTAL_DATOS; i_mask++) begin
            // Pausas aleatorias para comprobar la robustez del mask_valid
            if ($random % 4 == 0) begin
                mask_valid <= 0;
                repeat ($random % 3 + 1) @(posedge clk);
            end
            
            mask_valid <= 1;
            mask_bit <= mask_mem[i_mask];
            @(posedge clk);
        end

        // Finalizar inyección
        @(posedge clk);
        mask_valid <= 0;

        // Esperar a la señal done
        wait (done == 1'b1);
        @(posedge clk);
        
        $display("=== RESUMEN DE LA SIMULACION ===");
        $display("Punteros comprobados: %0d / %0d", i_ptr, N_SAMPLES);
        $display("Errores detectados: %0d", errores);
        if (errores == 0 && i_ptr == N_SAMPLES) begin
            $display(">> TEST PASADO EXITOSAMENTE <<");
        end else begin
            $display(">> TEST FALLIDO <<");
        end
        $finish;
    end

    // Proceso de verificación concurrente
    always @(posedge clk) begin
        if (read_en) begin
            current_ptr = ptr_mem[i_ptr];
            if (ram_addr !== current_ptr) begin
                $display("ERROR en tiempo %0t: Se genero addr %0h pero se esperaba %0h", $time, ram_addr, current_ptr);
                errores++;
            end
            i_ptr++;
        end
    end

endmodule
