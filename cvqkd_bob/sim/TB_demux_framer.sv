`timescale 1ns / 1ps

module tb_demux_framer();

    // =========================================================================
    // 1. Declaración de Señales y Parámetros
    // =========================================================================
    localparam DATA_WIDTH = 16;
    localparam NUM_SAMPLES = 1600; // 100 tramas * 16 muestras de MATLAB

    logic clk;
    logic rst;
    logic valid_in;
    logic signed [DATA_WIDTH-1:0] p_in;
    logic signed [DATA_WIDTH-1:0] q_in;

    logic [DATA_WIDTH*2-1:0] m_axis_cordic_tdata;
    logic                    m_axis_cordic_tvalid;
    logic [DATA_WIDTH*2-1:0] fifo_data_out;
    logic                    fifo_we;

    // Memoria virtual para almacenar los datos del archivo .txt
    logic [31:0] memoria_test [0:NUM_SAMPLES-1];

    // =========================================================================
    // 2. Instanciación del DUT (Device Under Test)
    // =========================================================================
    demux_framer #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .p_in(p_in),
        .q_in(q_in),
        .m_axis_cordic_tdata(m_axis_cordic_tdata),
        .m_axis_cordic_tvalid(m_axis_cordic_tvalid),
        .fifo_data_out(fifo_data_out),
        .fifo_we(fifo_we)
    );

    // =========================================================================
    // 3. Generación de Reloj (100 MHz -> Periodo de 10ns)
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // =========================================================================
    // 4. Proceso Principal de Estímulos
    // =========================================================================
    initial begin
        // A) Cargar el archivo generado por MATLAB
        // IMPORTANTE: Asegúrate de que input_vectors.txt esté en la carpeta raíz
        // de la simulación de Vivado, o pon la ruta absoluta (ej. "C:/ruta/input_vectors.txt")
        $readmemh("C:/Users/usser/Vivado_Sources/cvqkd_bob/Sim/input_vectors.txt", memoria_test);

        // B) Estado inicial
        rst = 1'b1;
        valid_in = 1'b0;
        p_in = '0;
        q_in = '0;

        // Esperamos 20ns y quitamos el reset (Sincronización de inicio)
        #20;
        rst = 1'b0;
        #10;

        $display("--- INICIANDO INYECCIÓN DE DATOS ---");

        // C) Inyectar 2 tramas completas (32 muestras) para comprobar el DEMUX
        for (int i = 0; i < 32; i++) begin
            @(posedge clk); // Esperamos al flanco de subida
            
            valid_in <= 1'b1;
            // MATLAB guardó {Q_IN_HEX, P_IN_HEX} (32 bits)
            q_in <= memoria_test[i][31:16]; // Extraemos los MSB
            p_in <= memoria_test[i][15:0];  // Extraemos los LSB
        end

        // D) Parar inyección
        @(posedge clk);
        valid_in <= 1'b0;

        // Esperar un poco para ver los últimos datos y terminar simulación
        #50;
        $display("--- SIMULACIÓN FINALIZADA ---");
        $finish;
    end

endmodule