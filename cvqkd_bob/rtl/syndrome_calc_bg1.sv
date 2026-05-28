`timescale 1ns / 1ps

import bg_rom_pkg::*; // Importamos la matriz H (MB=46, NB=68)

module syndrome_calc_bg1 (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    
    // Interfaz de lectura hacia la RAM donde están los bits U de Bob
    output logic [6:0]   u_addr,      // Direccionamiento de columnas (0 a 67)
    input  logic [383:0] u_data_in,   // Bus de 384 bits de entrada
    
    // Interfaz de control y salida
    output logic         done,
    output logic [383:0] syndrome_out [0:MB-1] // Array con el síndrome final
);

    // =========================================================================
    // 1. Memoria interna para acumular el Síndrome (46 bloques de 384 bits)
    // =========================================================================
    logic [383:0] s_mem [0:MB-1];
    
    // =========================================================================
    // 2. Instancia del Barrel Shifter Combinacional
    // =========================================================================
    logic [383:0] shift_data_in;
    logic [8:0]   shift_val;
    logic [383:0] shift_data_out;
    
    barrel_shifter_384 shifter_inst (
        .data_in(shift_data_in),
        .shift_val(shift_val),
        .data_out(shift_data_out)
    );

    // Conectamos la entrada del shifter siempre al dato leído de la RAM
    assign shift_data_in = u_data_in;

    // =========================================================================
    // 3. Máquina de Estados (FSM) - Control Path
    // =========================================================================
    typedef enum logic [2:0] {
        ST_IDLE, 
        ST_FETCH_U, 
        ST_WAIT_RAM,
        ST_PROCESS_ROW, 
        ST_DONE
    } state_t;
    
    state_t state, next_state;
    
    // Contadores para recorrer la matriz
    logic [6:0] col_cnt; // 0 a NB-1 (67)
    logic [5:0] row_cnt; // 0 a MB-1 (45)

    // Lectura del valor de desplazamiento de la ROM
    shortint current_shift_rom;
    assign current_shift_rom = BG_ROM[row_cnt][col_cnt];
    
    // Casteamos el valor al puerto del shifter (solo los 9 bits bajos)
    assign shift_val = current_shift_rom[8:0];

    // Lógica Secuencial de Estado y Datapath
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= ST_IDLE;
            col_cnt  <= '0;
            row_cnt  <= '0;
            done     <= 1'b0;
            for (int i = 0; i < MB; i++) s_mem[i] <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    col_cnt <= '0;
                    row_cnt <= '0;
                    if (start) begin
                        // Limpiamos la memoria del síndrome para un nuevo cálculo
                        for (int i = 0; i < MB; i++) s_mem[i] <= '0;
                        state <= ST_FETCH_U;
                    end
                end
                
                ST_FETCH_U: begin
                    // Pedimos la columna col_cnt a la RAM
                    u_addr <= col_cnt;
                    state  <= ST_WAIT_RAM;
                end
                
                ST_WAIT_RAM: begin
                    // Un ciclo de retardo para que la BRAM entregue el dato válido
                    state <= ST_PROCESS_ROW;
                end
                
                ST_PROCESS_ROW: begin
                    // Si el valor en la matriz H no es -1 (vacío)
                    if (current_shift_rom >= 0) begin
                        // Acumulamos mediante XOR: S_nuevo = S_anterior XOR U_rotado
                        s_mem[row_cnt] <= s_mem[row_cnt] ^ shift_data_out;
                    end
                    
                    // Lógica de bucles anidados
                    if (row_cnt == MB - 1) begin
                        row_cnt <= '0;
                        if (col_cnt == NB - 1) begin
                            state <= ST_DONE; // Terminamos todas las columnas
                        end else begin
                            col_cnt <= col_cnt + 1;
                            state   <= ST_FETCH_U; // Siguiente columna de U
                        end
                    end else begin
                        row_cnt <= row_cnt + 1; // Siguiente fila de la misma columna
                    end
                end
                
                ST_DONE: begin
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    // Asignación de la memoria interna a la salida del módulo
    always_comb begin
        for (int i = 0; i < MB; i++) begin
            syndrome_out[i] = s_mem[i];
        end
    end

endmodule