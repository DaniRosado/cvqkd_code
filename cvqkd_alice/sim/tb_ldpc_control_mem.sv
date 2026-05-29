`timescale 1ns / 1ps

module tb_ldpc_control_mem();

    // --- Parámetros ---
    localparam int Z = 384;
    localparam int W = 8;
    localparam int BUS_WIDTH = Z * W;
    localparam int PIPELINE_DEPTH = 6; // Ajustable

    // --- Señales de Reloj y Reset ---
    logic clk;
    logic rst_n;
    
    // --- Señales de Control ---
    logic start_decoding;
    logic decoding_done;
    
    // --- Interfaces FSM <-> Memorias ---
    logic [6:0] p_read_addr, p_write_addr;
    logic [8:0] r_read_addr, r_write_addr;
    logic       p_write_en,  r_write_en;
    
    logic       datapath_valid_in;
    logic [8:0] datapath_shift;

    // --- Buses de Datos ---
    logic [BUS_WIDTH-1:0] p_read_data, r_read_data;
    logic [BUS_WIDTH-1:0] fake_p_write_data, fake_r_write_data;

    // ==========================================
    // 1. GENERACIÓN DE RELOJ (100 MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // ==========================================
    // 2. INSTANCIACIÓN DE MÓDULOS (DUT)
    // ==========================================
    
    // El Controlador
    ldpc_controller_fsm #(
        .PIPELINE_DEPTH(PIPELINE_DEPTH)
    ) dut_fsm (
        .clk              (clk),
        .rst_n            (rst_n),
        .start_decoding   (start_decoding),
        .p_read_addr      (p_read_addr),
        .r_read_addr      (r_read_addr),
        .datapath_valid_in(datapath_valid_in),
        .datapath_shift   (datapath_shift),
        .p_write_en       (p_write_en),
        .p_write_addr     (p_write_addr),
        .r_write_en       (r_write_en),
        .r_write_addr     (r_write_addr),
        .decoding_done    (decoding_done)
    );

    // BRAM de Variables (L)
    L_BRAM #(
        .Z(Z), .W(W)
    ) dut_p_mem (
        .clk        (clk),
        .read_addr  (p_read_addr),
        .read_data  (p_read_data),
        .write_en   (p_write_en),
        .write_addr (p_write_addr),
        .write_data (fake_p_write_data)
    );

    // BRAM de Mensajes (R)
    R_BRAM #(
        .Z(Z), .W(W)
    ) dut_r_mem (
        .clk        (clk),
        .read_addr  (r_read_addr),
        .read_data  (r_read_data),
        .write_en   (r_write_en),
        .write_addr (r_write_addr),
        .write_data (fake_r_write_data)
    );

    // ==========================================
    // 3. MOCK DEL DATAPATH (Simulación de cálculos)
    // ==========================================
    // Como no tenemos VNUs ni CNUs, inventamos datos para escribir en memoria
    // usando la dirección de escritura como semilla, para luego poder comprobarlo.
    always_comb begin
        // Rellenamos todo el bus gigante con el número de la dirección
        fake_p_write_data = {(BUS_WIDTH/7){p_write_addr}}; 
        fake_r_write_data = {(BUS_WIDTH/9){r_write_addr}};
    end

    // ==========================================
    // 4. ESTÍMULOS Y MONITORES
    // ==========================================
    initial begin
        // Estado inicial
        rst_n = 0;
        start_decoding = 0;
        
        $display("==================================================");
        $display("[TB] Iniciando simulación del Subsistema de Control");
        $display("==================================================");

        // Reset
        #20;
        rst_n = 1;
        #15;
        
        // Disparar la decodificación
        $display("[TB] %0t: Lanzando start_decoding...", $time);
        @(posedge clk);
        start_decoding = 1;
        @(posedge clk);
        start_decoding = 0;

        // Monitorear eventos críticos
        // Esperamos a ver qué hace la FSM
        fork
            begin
                // Monitor de lecturas
                forever begin
                    @(posedge clk);
                    if (datapath_valid_in) begin
                        $display("[TB-READ]  %0t: FSM solicita leer P_MEM[%0d] y R_MEM[%0d] | Shift: %0d", 
                                 $time, p_read_addr, r_read_addr, datapath_shift);
                    end
                end
            end
            begin
                // Monitor de escrituras (Pipeline retrasado)
                forever begin
                    @(posedge clk);
                    if (p_write_en) begin
                        $display("[TB-WRITE] %0t: FSM ordena escribir P_MEM[%0d] y R_MEM[%0d] tras el pipeline", 
                                 $time, p_write_addr, r_write_addr);
                    end
                end
            end
            begin
                // Timeout de seguridad
                #10000; 
                $display("[TB] Timeout alcanzado. Revisa la FSM.");
                $finish;
            end
            begin
                // Esperar a que termine
                wait (decoding_done == 1'b1);
                $display("[TB] %0t: ¡Decodificación completada con éxito!", $time);
                $finish;
            end
        join_any
    end

endmodule