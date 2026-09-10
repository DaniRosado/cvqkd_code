`timescale 1ns / 1ps

module demux_framer #(
    parameter DATA_WIDTH = 16 // ADC de 16 bits
)(
    input  logic clk,
    input  logic rst,         // Reset síncrono (Usado como Sync de Trama)
    input  logic valid_in,    // Señal que indica que hay un dato nuevo del ADC
    
    // Entradas de datos Q1.15
    input  logic signed [DATA_WIDTH-1:0] p_in,
    input  logic signed [DATA_WIDTH-1:0] q_in,

    // Salida 1: Hacia el CORDIC VECT (AXI4-Stream)
    output logic [DATA_WIDTH*2-1:0] m_axis_cordic_tdata,
    output logic                    m_axis_cordic_tvalid,

    // Salida 2: Hacia la FIFO de retraso
    output logic [DATA_WIDTH*2-1:0] fifo_data_out,
    output logic                    fifo_we  // Write Enable de la FIFO
);

    // =========================================================================
    // 1. Contador de Trama (Máquina de Estados)
    // =========================================================================
    logic [3:0] frame_counter; // Contador de 4 bits (0 a 15)

    always_ff @(posedge clk) begin
        if (rst) begin
            frame_counter <= 4'd0; // Sincronización al inicio de trama
        end 
        else if (valid_in) begin
            // Al ser de 4 bits, al llegar a 15 pasará automáticamente a 0
            // No hace falta poner un "if (counter == 15)"
            frame_counter <= frame_counter + 1'b1; 
        end
    end

    // =========================================================================
    // 2. Empaquetado de Datos (AXI-Stream Format: {Y, X} -> {Q, P})
    // =========================================================================
    logic [DATA_WIDTH*2-1:0] packed_data;
    assign packed_data = {q_in, p_in}; // Concatenación de 32 bits

    // Las conexiones de datos siempre están conectadas (es más eficiente en hardware)
    // Lo que realmente "enruta" el dato son las señales "valid" y "we".
    assign m_axis_cordic_tdata = packed_data;
    assign fifo_data_out       = packed_data;

    // =========================================================================
    // 3. Lógica de Enrutamiento (El "DEMUX" real)
    // =========================================================================
    always_comb begin
        // Valores por defecto (Buena práctica en SystemVerilog para evitar Latch)
        m_axis_cordic_tvalid = 1'b0;
        fifo_we              = 1'b0;

        if (valid_in) begin
            if (frame_counter == 4'd0) begin
                // Estamos en el Índice 0: Es el Piloto. Se lo mandamos al CORDIC
                m_axis_cordic_tvalid = 1'b1;
            end 
            else begin
                // Índices 1 al 15: Son Datos. Se los mandamos a la FIFO
                fifo_we = 1'b1;
            end
        end
    end

endmodule