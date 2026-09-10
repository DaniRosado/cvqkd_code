`timescale 1ns / 1ps

module sync_fifo #(
    parameter DATA_WIDTH = 32, // 16 bits Q + 16 bits P
    parameter DEPTH = 64       // Profundidad (OBLIGATORIO: que sea potencia de 2)
)(
    input  logic clk,
    input  logic rst,
    
    // Puertos de Escritura (Vienen del DEMUX)
    input  logic we,           // Write Enable
    input  logic [DATA_WIDTH-1:0] din,
    
    // Puertos de Lectura (Irán al CORDIC 2 de Rotación)
    input  logic re,           // Read Enable
    output logic [DATA_WIDTH-1:0] dout,
    
    // Banderas de Estado
    output logic empty,        // 1 si está vacía
    output logic full          // 1 si está llena
);

    // =========================================================================
    // 1. Declaración de la Memoria y Punteros
    // =========================================================================
    // mem es un array de 64 posiciones, cada una de 32 bits.
    // Vivado inferirá esto automáticamente como "Distributed RAM" o "Block RAM"
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Calculamos los bits necesarios para los punteros según la DEPTH
    // $clog2(64) = 6 bits. Con 6 bits contamos de 0 a 63.
    localparam PTR_WIDTH = $clog2(DEPTH);
    
    logic [PTR_WIDTH-1:0] wr_ptr; // Puntero de escritura
    logic [PTR_WIDTH-1:0] rd_ptr; // Puntero de lectura
    
    // Contador para saber cuántos elementos hay dentro (necesita 1 bit más que el puntero)
    logic [PTR_WIDTH:0] count;

    // =========================================================================
    // 2. Banderas (Lógica Combinacional)
    // =========================================================================
    assign empty = (count == 0);
    assign full  = (count == DEPTH);

    // =========================================================================
    // 3. Control de Lectura, Escritura y Punteros (Lógica Secuencial)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
            dout   <= '0;
        end else begin
            
            // --- BLOQUE DE ESCRITURA ---
            if (we && !full) begin
                mem[wr_ptr] <= din;
                // Al ser de 6 bits, al llegar a 63, el +1 lo desborda y vuelve a 0 solo.
                // ¡Magia de los buffers circulares!
                wr_ptr <= wr_ptr + 1'b1;
            end
            
            // --- BLOQUE DE LECTURA ---
            if (re && !empty) begin
                dout <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1'b1;
            end
            
            // --- ACTUALIZACIÓN DEL CONTADOR ---
            // Manejamos los casos donde se lee y escribe a la vez en el mismo ciclo de reloj
            if ((we && !full) && !(re && !empty)) begin
                count <= count + 1'b1; // Solo entra dato
            end 
            else if ((re && !empty) && !(we && !full)) begin
                count <= count - 1'b1; // Solo sale dato
            end
            // Si entran y salen datos a la vez, el contador se queda igual.
        end
    end

endmodule