`timescale 1ns / 1ps

module ping_pong_bram #(
    parameter DATA_WIDTH = 32,    // 16 bits Q + 16 bits P
    parameter BLOCK_SIZE = 52224, // Muestras exactas por buffer
    parameter ADDR_WIDTH = 17     // 2^17 = 131072 posiciones totales
)(
    // =========================================================
    // PUERTO A: ESCRITURA (Viene de tu DSP_TOP a 100 MHz)
    // =========================================================
    input  logic               clk_wr,
    input  logic               rst,
    input  logic signed [15:0] p_in,      // p_out del DSP
    input  logic signed [15:0] q_in,      // q_out del DSP
    input  logic               valid_in,  // valid_out del DSP

    // =========================================================
    // PUERTO B: LECTURA (Para la CPU / Bloque de Estimación)
    // =========================================================
    input  logic               clk_rd,    // Reloj de lectura (puede ser el de la CPU)
    input  logic [ADDR_WIDTH-1:0] rd_addr,   // Qué dirección queremos leer
    output logic [DATA_WIDTH-1:0] rd_data,   // Dato extraído {Q, P}

    // =========================================================
    // SEÑALES DE CONTROL (Hacia el procesador)
    // =========================================================
    output logic               buffer_ready_irq, // Pulso de 1 ciclo: "¡Buffer Lleno!"
    output logic               buffer_to_read    // 0 = Leer Mitad A | 1 = Leer Mitad B
);

    // 1. INFERENCIA DE MEMORIA BRAM (True Dual Port)
    // El atributo (* ram_style = "block" *) fuerza a Vivado a usar BRAMs físicas 
    // y no compuertas lógicas (LUTs), lo cual es vital para memorias grandes.
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // 2. REGISTROS INTERNOS DE ESCRITURA
    logic [15:0] write_counter; // Cuenta de 0 a 52223 (16 bits es suficiente)
    logic        wr_ping_pong;  // 0 = Escribiendo en A, 1 = Escribiendo en B
    
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [DATA_WIDTH-1:0] wr_data;

    // Empaquetamos los datos
    assign wr_data = {q_in, p_in};
    
    // Formamos la dirección uniendo el bit selector y el contador
    assign wr_addr = {wr_ping_pong, write_counter};

    // 3. LÓGICA DE CONTROL PING-PONG
    always_ff @(posedge clk_wr) begin
        if (rst) begin
            write_counter    <= '0;
            wr_ping_pong     <= 1'b0; // Empezamos llenando el Ping (A)
            buffer_ready_irq <= 1'b0;
            buffer_to_read   <= 1'b0;
        end else begin
            // La interrupción por defecto es 0 (solo da un pulso de 1 ciclo)
            buffer_ready_irq <= 1'b0; 

            if (valid_in) begin
                // A) Escribimos en memoria
                ram[wr_addr] <= wr_data;

                // B) Controlamos el contador
                if (write_counter == BLOCK_SIZE - 1) begin
                    // ¡Buffer Lleno!
                    write_counter    <= '0;                  // Reiniciamos cuenta
                    wr_ping_pong     <= ~wr_ping_pong;       // Cambiamos de buffer (Ping -> Pong)
                    
                    // Avisamos a la CPU
                    buffer_ready_irq <= 1'b1;                // ¡Dispara la interrupción!
                    buffer_to_read   <= wr_ping_pong;        // Le decimos a la CPU qué mitad se acaba de llenar
                end else begin
                    // Seguimos contando
                    write_counter <= write_counter + 1'b1;
                end
            end
        end
    end

    // 4. LÓGICA DE LECTURA (Puerto Independiente)
    // La lectura en BRAM siempre tiene 1 ciclo de latencia (estándar FPGA)
    always_ff @(posedge clk_rd) begin
        rd_data <= ram[rd_addr];
    end

endmodule