`timescale 1ns / 1ps

module R_BRAM #(
    parameter int Z         = 384,
    parameter int W         = 8,
    parameter int BUS_WIDTH = Z * W  // 3072 bits
)(
    input  logic                 clk,
    
    // Puerto de Lectura (1 ciclo de latencia)
    input  logic [8:0]           read_addr,   // 0 a 315 (316 conexiones válidas)
    output logic [BUS_WIDTH-1:0] read_data,
    
    // Puerto de Escritura
    input  logic                 write_en,
    input  logic [8:0]           write_addr,
    input  logic [BUS_WIDTH-1:0] write_data
);

    (* ram_style = "block" *) logic [BUS_WIDTH-1:0] mem [0:315];

    initial begin
        for (int i = 0; i < 316; i++) begin
            mem[i] = '0;
        end
    end

    always_ff @(posedge clk) begin
        if (write_en) begin
            mem[write_addr] <= write_data;
        end
        read_data <= mem[read_addr];
    end

endmodule