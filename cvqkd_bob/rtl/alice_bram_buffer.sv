`timescale 1ns / 1ps

module alice_bram_buffer #(
    parameter DATA_WIDTH = 32,    // 16 bits Q_A + 16 bits P_A
    parameter ADDR_WIDTH = 15     // 2^15 = 32768 posiciones
)(
    input  logic                  clk,
    input  logic                  rst,

    // Puerto de escritura (desde DMA / Ethernet)
    input  logic                  we,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [DATA_WIDTH-1:0] wr_data,

    // Puerto de lectura (para el acelerador matemático)
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data,

    // Control de flujo
    output logic [ADDR_WIDTH:0]   items_avail
);

    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // Contador de escritura
    logic [ADDR_WIDTH:0] wr_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_count <= '0;
        end else if (we) begin
            ram[wr_addr] <= wr_data;
            wr_count <= wr_count + 1'b1;
        end
    end

    // Lectura con 1 ciclo de latencia
    always_ff @(posedge clk) begin
        rd_data <= ram[rd_addr];
    end

    assign items_avail = wr_count;

endmodule
