`timescale 1ns / 1ps

module ptr_ram_buffer #(
    parameter DATA_WIDTH = 16,    // 16 bits para almacenar ram_addr
    parameter ADDR_WIDTH = 15     // 2^15 = 32768 posiciones totales
)(
    // =========================================================
    // PUERTO A: ESCRITURA (Conectado a generador_direcciones_bob)
    // =========================================================
    input  logic                  clk_wr,
    input  logic                  rst_wr,
    input  logic                  we,         // Conectar al 'read_en' del generador
    input  logic [DATA_WIDTH-1:0] wr_data,    // Conectar al 'ram_addr' del generador

    // =========================================================
    // PUERTO B: LECTURA (Conectado al param_estimator / FSM)
    // =========================================================
    input  logic                  clk_rd,
    input  logic                  rst_rd,
    input  logic [ADDR_WIDTH-1:0] rd_addr,    // Conectar al 'ptr_addr' del FSM
    output logic [DATA_WIDTH-1:0] rd_data,    // Conectar al 'ptr_data' del FSM
    
    // =========================================================
    // CONTROL DE FLUJO ON-THE-FLY
    // =========================================================
    output logic [ADDR_WIDTH:0]   items_avail // Datos listos (Sincronizado a clk_rd)
);

    // INFERENCIA DE MEMORIA BRAM
    // Obligamos a Vivado a usar RAM física en el silicio
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // =========================================================
    // LÓGICA DE ESCRITURA Y AUTO-INCREMENTO
    // =========================================================
    logic [ADDR_WIDTH:0] wr_count;

    always_ff @(posedge clk_wr) begin
        if (rst_wr) begin
            wr_count <= '0;
        end else if (we) begin
            // Guardamos la dirección generada en nuestra memoria interna
            ram[wr_count[ADDR_WIDTH-1:0]] <= wr_data;
            // Avanzamos el puntero de escritura automáticamente
            wr_count <= wr_count + 1'b1;
        end
    end

    // =========================================================
    // LÓGICA DE LECTURA (Latencia de 1 ciclo)
    // =========================================================
    always_ff @(posedge clk_rd) begin
        rd_data <= ram[rd_addr];
    end

    // =========================================================
    // LÓGICA DE CRUCE DE DOMINIOS (CDC) PARA CONTROL DE FLUJO
    // =========================================================
    logic [ADDR_WIDTH:0] wr_count_gray;
    logic [ADDR_WIDTH:0] wr_count_gray_sync1;
    logic [ADDR_WIDTH:0] wr_count_gray_sync2;
    logic [ADDR_WIDTH:0] rd_items_avail_bin;

    // 1. Conversión Binario a Gray (Dominio clk_wr)
    assign wr_count_gray = (wr_count >> 1) ^ wr_count;

    // 2. Sincronizador de doble registro (Dominio clk_rd)
    always_ff @(posedge clk_rd) begin
        if (rst_rd) begin
            wr_count_gray_sync1 <= '0;
            wr_count_gray_sync2 <= '0;
        end else begin
            wr_count_gray_sync1 <= wr_count_gray;
            wr_count_gray_sync2 <= wr_count_gray_sync1;
        end
    end

    // 3. Conversión Gray a Binario (Dominio clk_rd)
    always_comb begin
        rd_items_avail_bin[ADDR_WIDTH] = wr_count_gray_sync2[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) begin
            rd_items_avail_bin[i] = rd_items_avail_bin[i+1] ^ wr_count_gray_sync2[i];
        end
    end

    // 4. Asignación de salida segura hacia el FSM
    assign items_avail = rd_items_avail_bin;

endmodule
