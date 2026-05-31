`timescale 1ns / 1ps

module ping_pong_bram #(
    parameter DATA_WIDTH = 32,    // 16 bits Q + 16 bits P
    parameter BLOCK_SIZE = 52224, // Muestras exactas por buffer
    parameter ADDR_WIDTH = 17     // 2^17 = 131072 posiciones totales
)(
    input  logic               clk,
    input  logic               rst,

    // Puerto de escritura (desde el DSP)
    input  logic signed [15:0] p_in,
    input  logic signed [15:0] q_in,
    input  logic               valid_in,

    // Puerto de lectura (para estimación de parámetros / síndrome)
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data,

    // Señales de control
    output logic               buffer_ready_irq,
    output logic               buffer_to_read    // 0 = Leer Mitad A | 1 = Leer Mitad B
);

    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    logic [15:0] write_counter;
    logic        wr_ping_pong;

    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [DATA_WIDTH-1:0] wr_data;

    assign wr_data = {q_in, p_in};
    assign wr_addr = {wr_ping_pong, write_counter};

    always_ff @(posedge clk) begin
        if (rst) begin
            write_counter    <= '0;
            wr_ping_pong     <= 1'b0;
            buffer_ready_irq <= 1'b0;
            buffer_to_read   <= 1'b0;
        end else begin
            buffer_ready_irq <= 1'b0;

            if (valid_in) begin
                ram[wr_addr] <= wr_data;

                if (write_counter == BLOCK_SIZE - 1) begin
                    write_counter    <= '0;
                    wr_ping_pong     <= ~wr_ping_pong;
                    buffer_ready_irq <= 1'b1;
                    buffer_to_read   <= wr_ping_pong;
                end else begin
                    write_counter <= write_counter + 1'b1;
                end
            end
        end
    end

    // Lectura con 1 ciclo de latencia (inferencia BRAM estándar)
    always_ff @(posedge clk) begin
        rd_data <= ram[rd_addr];
    end

endmodule