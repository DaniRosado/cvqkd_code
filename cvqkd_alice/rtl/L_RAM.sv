`timescale 1ns / 1ps

module L_BRAM #(
    parameter int Z         = 384,
    parameter int W         = 8,
    parameter int BUS_WIDTH = Z * W  // 3072 bits
)(
    input  logic                 clk,
    
    // Puerto de Lectura (Siempre síncrono, tarda 1 ciclo)
    input  logic [6:0]           read_addr,   // 0 a 67 (68 columnas BG1)
    output logic [BUS_WIDTH-1:0] read_data,
    
    // Puerto de Escritura (Para actualización en caliente o carga inicial)
    input  logic                 write_en,
    input  logic [6:0]           write_addr,
    input  logic [BUS_WIDTH-1:0] write_data
);

    // Directiva para forzar el uso de Block RAM físicos
    (* ram_style = "block" *) logic [BUS_WIDTH-1:0] mem [0:67];

    // Lógica de lectura y escritura síncrona recomendada por Xilinx
    always_ff @(posedge clk) begin
        if (write_en) begin
            mem[write_addr] <= write_data;
        end
        // Al registrar la salida directamente desde el array, 
        // Vivado infiere la estructura nativa de la BRAM (1 ciclo de latencia)
        read_data <= mem[read_addr];
    end

endmodule