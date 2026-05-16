`timescale 1ns / 1ps

module alice_bram_buffer #(
    parameter DATA_WIDTH = 32,    // 16 bits Q_A + 16 bits P_A
    parameter ADDR_WIDTH = 15     // 2^15 = 32768 posiciones totales
)(
    // =========================================================
    // PUERTO A: ESCRITURA (Conectado al DMA / Red Ethernet)
    // =========================================================
    input  logic                  clk_wr,     // Reloj del bus del procesador
    input  logic                  rst_wr,     // Reset del dominio de escritura
    input  logic                  we,         // Write Enable (Habilita la escritura)
    input  logic [ADDR_WIDTH-1:0] wr_addr,    // Dirección donde guardar (0 a 26111)
    input  logic [DATA_WIDTH-1:0] wr_data,    // Dato que llega de Alice {Q_A, P_A}

    // =========================================================
    // PUERTO B: LECTURA (Conectado a tu Acelerador Matemático)
    // =========================================================
    input  logic                  clk_rd,     // Reloj del DSP (100 MHz)
    input  logic                  rst_rd,     // Reset del dominio de lectura
    input  logic [ADDR_WIDTH-1:0] rd_addr,    // Dirección que el acelerador quiere leer
    output logic [DATA_WIDTH-1:0] rd_data,    // Dato extraído hacia los multiplicadores
    
    // =========================================================
    // CONTROL DE FLUJO ON-THE-FLY
    // =========================================================
    output logic [ADDR_WIDTH:0]   items_avail // Cantidad de datos listos (Sincronizado a clk_rd)
);

    // INFERENCIA DE MEMORIA BRAM
    // Obligamos a Vivado a usar RAM física en el silicio
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // LÓGICA DE ESCRITURA
    always_ff @(posedge clk_wr) begin
        if (we) begin
            ram[wr_addr] <= wr_data;
        end
    end

    // LÓGICA DE LECTURA (Latencia de 1 ciclo)
    always_ff @(posedge clk_rd) begin
        rd_data <= ram[rd_addr];
    end

    // =========================================================
    // LÓGICA DE CRUCE DE DOMINIOS (CDC) PARA CONTROL DE FLUJO
    // =========================================================
    logic [ADDR_WIDTH:0] wr_count;
    logic [ADDR_WIDTH:0] wr_count_gray;

    // Sincronizadores en el dominio de lectura
    logic [ADDR_WIDTH:0] wr_count_gray_sync1;
    logic [ADDR_WIDTH:0] wr_count_gray_sync2;
    logic [ADDR_WIDTH:0] rd_items_avail_bin;

    // 1. Contador de escritura binario
    always_ff @(posedge clk_wr) begin
        if (rst_wr) begin
            wr_count <= '0;
        end else if (we) begin
            wr_count <= wr_count + 1'b1;
        end
    end

    // 2. Conversión Binario a Gray (Dominio clk_wr)
    assign wr_count_gray = (wr_count >> 1) ^ wr_count;

    // 3. Sincronizador de doble registro (Dominio clk_rd)
    always_ff @(posedge clk_rd) begin
        if (rst_rd) begin
            wr_count_gray_sync1 <= '0;
            wr_count_gray_sync2 <= '0;
        end else begin
            wr_count_gray_sync1 <= wr_count_gray;
            wr_count_gray_sync2 <= wr_count_gray_sync1;
        end
    end

    // 4. Conversión Gray a Binario (Dominio clk_rd)
    always_comb begin
        rd_items_avail_bin[ADDR_WIDTH] = wr_count_gray_sync2[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) begin
            rd_items_avail_bin[i] = rd_items_avail_bin[i+1] ^ wr_count_gray_sync2[i];
        end
    end

    // 5. Asignación de salida segura
    assign items_avail = rd_items_avail_bin;

endmodule