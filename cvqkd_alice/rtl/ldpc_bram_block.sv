`timescale 1ns / 1ps

module ldpc_bram_block #(
    parameter int Z = 384,
    parameter int W = 8,
    parameter int DEPTH = 68
)(
    input  logic                 clk,
    
    // Puerto A: Lectura/Escritura del Decodificador (Bus de 3072 bits)
    input  logic [$clog2(DEPTH)-1:0] addr_a,
    input  logic [Z*W-1:0]           din_a,
    input  logic                     we_a,
    output logic [Z*W-1:0]           dout_a,
    
    // Puerto B: Interfaz externa (opcional, para carga/descarga)
    input  logic [$clog2(DEPTH)-1:0] addr_b,
    output logic [Z*W-1:0]           dout_b
);

    // Definición de la memoria: 68 filas de 3072 bits cada una
    (* ram_style = "block" *) // Atributo para forzar el uso de BRAM en Xilinx
    logic [Z*W-1:0] ram [0:DEPTH-1];

    // Puerto A
    always_ff @(posedge clk) begin
        if (we_a) begin
            ram[addr_a] <= din_a;
        end
        dout_a <= ram[addr_a];
    end

    // Puerto B (Solo lectura)
    always_ff @(posedge clk) begin
        dout_b <= ram[addr_b];
    end

endmodule