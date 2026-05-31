`timescale 1ns / 1ps

import bg1_rom_pkg::*;

module syndrome_calc_bg1 (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,

    // Interfaz de lectura hacia la RAM de bits U de Bob
    output logic [6:0]   u_addr,      // Columna del base graph (0 a 67)
    input  logic [383:0] u_data_in,   // Bus de 384 bits

    // Salida
    output logic         done,
    output logic [383:0] syndrome_out [0:45]
);

    localparam int Z = 384;
    localparam int TOTAL_EDGES = 316;

    // Memoria interna del síndrome (46 filas de 384 bits)
    logic [Z-1:0] s_mem [0:45];

    // Barrel shifter combinacional
    logic [Z-1:0] shift_data_out;
    logic [8:0]   shift_val;

    barrel_shifter_384 shifter_inst (
        .data_in  (u_data_in),
        .shift_val(shift_val),
        .data_out (shift_data_out)
    );

    // FSM
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_FETCH,
        ST_WAIT_RAM,
        ST_ACCUMULATE,
        ST_DONE
    } state_t;

    state_t state;

    // Contadores
    logic [8:0]  edge_ptr;     // 0 a 315
    logic [5:0]  row_idx;      // Fila actual (0 a 45)
    logic [5:0]  edge_in_row;  // Edge dentro de la fila actual

    // Lectura de la ROM
    edge_info_t current_edge;
    row_info_t  current_row_info;

    assign current_edge     = EDGE_ROM[edge_ptr];
    assign current_row_info = ROW_INFO_ROM[row_idx];
    assign u_addr           = current_edge.col_idx;
    assign shift_val        = current_edge.shift_val;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            edge_ptr    <= '0;
            row_idx     <= '0;
            edge_in_row <= '0;
            done        <= 1'b0;
            for (int i = 0; i < 46; i++) s_mem[i] <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        edge_ptr    <= '0;
                        row_idx     <= '0;
                        edge_in_row <= '0;
                        for (int i = 0; i < 46; i++) s_mem[i] <= '0;
                        state <= ST_FETCH;
                    end
                end

                ST_FETCH: begin
                    // u_addr ya apunta a la columna correcta (combinacional)
                    state <= ST_WAIT_RAM;
                end

                ST_WAIT_RAM: begin
                    // 1 ciclo de latencia de la BRAM
                    state <= ST_ACCUMULATE;
                end

                ST_ACCUMULATE: begin
                    // XOR del dato rotado con el acumulador de la fila actual
                    s_mem[row_idx] <= s_mem[row_idx] ^ shift_data_out;

                    // Avanzar al siguiente edge
                    if (edge_ptr == TOTAL_EDGES - 1) begin
                        state <= ST_DONE;
                    end else begin
                        edge_ptr <= edge_ptr + 1;

                        // Comprobar si hemos terminado esta fila
                        if (edge_in_row == current_row_info.num_edges - 1) begin
                            row_idx     <= row_idx + 1;
                            edge_in_row <= '0;
                        end else begin
                            edge_in_row <= edge_in_row + 1;
                        end

                        state <= ST_FETCH;
                    end
                end

                ST_DONE: begin
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    // Salida
    always_comb begin
        for (int i = 0; i < 46; i++) begin
            syndrome_out[i] = s_mem[i];
        end
    end

endmodule
