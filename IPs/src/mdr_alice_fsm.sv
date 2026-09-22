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

    typedef enum logic [1:0] {IDLE, FEED_BLOCK, WAIT_MAC, DONE_STATE} state_t;
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
                if (start) next_state = FEED_BLOCK;
            end

            FEED_BLOCK: begin
                // Disparamos la lectura de memoria y avisamos al Datapath
                ram_read_en   = 1'b1;
                dp_valid_in   = 1'b1; 
                wait_cnt_next = 3'd1; // Iniciamos el contador de espera
                next_state    = WAIT_MAC;
            end

            WAIT_MAC: begin
                // Mantenemos la lectura y el valid apagados mientras el Datapath trabaja
                wait_cnt_next = wait_cnt + 1;
                
                // El Datapath tarda 8 ciclos totales. (1 del FEED_BLOCK + 7 aquí)
                if (wait_cnt == 3'd7) begin
                    block_cnt_next = block_cnt + 1;
                    
                    if (block_cnt == TOTAL_BLOCKS - 1) begin
                        next_state = DONE_STATE; // Si era el último, terminamos
                    end else begin
                        next_state = FEED_BLOCK; // Si no, inyectamos el siguiente
                    end
                end
            end

            DONE_STATE: begin
                done = 1'b1;
                if (!start) next_state = IDLE;
            end
        endcase
    end

    // El puntero de la memoria RAM es directamente la cuenta de bloques
    assign ram_read_addr = block_cnt;

endmodule