`timescale 1ns / 1ps

module mdr_alice_fsm #(
    parameter int TOTAL_BLOCKS = 13056
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,

    output logic        ram_read_en,
    output logic [13:0] ram_read_addr,
    output logic        dp_valid_in,
    
    output logic        done
);

    typedef enum logic [1:0] {IDLE, READ_RAM, WAIT_MAC, DONE_STATE} state_t;
    state_t state, next_state;

    logic [13:0] block_cnt, block_cnt_next; // Cuenta por qué bloque de datos vamos
    logic [2:0]  wait_cnt, wait_cnt_next;   // Cuenta los 8 ciclos de reloj internos

    // --- Registros de Estado ---
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state     <= IDLE;
            block_cnt <= '0;
            wait_cnt  <= '0;
        end else begin
            state     <= next_state;
            block_cnt <= block_cnt_next;
            wait_cnt  <= wait_cnt_next;
        end
    end

    // --- Lógica Combinacional de Transición ---
    always_comb begin
        next_state     = state;
        block_cnt_next = block_cnt;
        wait_cnt_next  = wait_cnt;
        
        ram_read_en = 1'b0;
        dp_valid_in = 1'b0;
        done        = 1'b0;

        case (state)
            IDLE: begin
                block_cnt_next = '0;
                wait_cnt_next  = '0;
                if (start) begin
                    ram_read_en = 1'b1;
                    next_state  = READ_RAM;
                end
            end

            READ_RAM: begin
                // En este ciclo la BRAM síncrona presenta el dato estable a la salida
                dp_valid_in   = 1'b1;
                wait_cnt_next = 3'd1;
                next_state    = WAIT_MAC;
            end

            WAIT_MAC: begin
                wait_cnt_next = wait_cnt + 1;
                
                // En el ciclo 7 (penúltimo), preparamos la lectura del siguiente bloque si no es el último
                if (wait_cnt == 3'd7) begin
                    if (block_cnt == TOTAL_BLOCKS - 1) begin
                        next_state = DONE_STATE;
                    end else begin
                        block_cnt_next = block_cnt + 1;
                        ram_read_en    = 1'b1;
                        next_state     = READ_RAM;
                    end
                end
            end

            DONE_STATE: begin
                done = 1'b1;
                if (!start) next_state = IDLE;
            end
        endcase
    end

    // El puntero de lectura hacia la BRAM pre-direcciona el siguiente bloque en el último ciclo de WAIT_MAC
    assign ram_read_addr = (state == WAIT_MAC && wait_cnt == 3'd7 && block_cnt != TOTAL_BLOCKS - 1) ? (block_cnt + 14'd1) : block_cnt;

endmodule