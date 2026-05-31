`timescale 1ns / 1ps

module ptr_ram_buffer #(
    parameter DATA_WIDTH = 16,    // 16 bits para almacenar ram_addr
    parameter ADDR_WIDTH = 15     // 2^15 = 32768 posiciones
)(
    input  logic                  clk,
    input  logic                  rst,

    // Puerto de escritura (desde generador_direcciones_bob)
    input  logic                  we,
    input  logic [DATA_WIDTH-1:0] wr_data,

    // Puerto de lectura (para param_estimator / FSM)
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data,

    // Control de flujo
    output logic [ADDR_WIDTH:0]   items_avail
);

    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    logic [ADDR_WIDTH:0] wr_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_count <= '0;
        end else if (we) begin
            ram[wr_count[ADDR_WIDTH-1:0]] <= wr_data;
            wr_count <= wr_count + 1'b1;
        end
    end

    // Lectura con 1 ciclo de latencia
    always_ff @(posedge clk) begin
        rd_data <= ram[rd_addr];
    end

    assign items_avail = wr_count;

endmodule
