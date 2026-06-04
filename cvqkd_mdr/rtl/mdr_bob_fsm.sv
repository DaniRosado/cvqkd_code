// ============================================================================
// Módulo:       mdr_bob_fsm
// Proyecto:     CV-QKD Hardware Accelerator
// Descripción:  FSM de control de lectura/escritura de RAM para el módulo MDR Bob
// Dependencias: mdr_bob_pkg.sv
// ----------------------------------------------------------------------------
// Notas de Arquitectura:
// Diseño altamente pipelinizado (Latencia total: 4 estados + flush).
// ============================================================================

`timescale 1ns / 1ps

module mdr_bob_fsm #(
    parameter int TOTAL_BLOCKS = 13056 // 52224 datos / 4 símbolos complejos
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        dp_valid_out,  // Nos avisa de que el Datapath escupe datos

    output logic        ram_read_en,
    output logic [13:0] ram_read_addr,
    output logic        dp_valid_in,   // Le dice al Datapath que lea
    
    output logic        ram_write_en,
    output logic [13:0] ram_write_addr,
    output logic        done
);

    typedef enum logic [1:0] {IDLE, PROCESSING, FLUSHING, DONE_STATE} state_t;
    state_t state, next_state;

    logic [13:0] raddr_reg, raddr_next;
    logic [13:0] waddr_reg, waddr_next;

    // --- Registros de Estado ---
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state     <= IDLE;
            raddr_reg <= '0;
            waddr_reg <= '0;
        end else begin
            state     <= next_state;
            raddr_reg <= raddr_next;
            
            // El puntero de escritura avanza automáticamente cuando el Datapath escupe datos
            if (dp_valid_out) begin
                waddr_reg <= waddr_reg + 1;
            end
        end
    end

    // --- Lógica Combinacional de Transición ---
    always_comb begin
        next_state    = state;
        raddr_next    = raddr_reg;
        ram_read_en   = 1'b0;
        dp_valid_in   = 1'b0;
        done          = 1'b0;

        case (state)
            IDLE: begin
                raddr_next = '0;
                if (start) next_state = PROCESSING;
            end

            PROCESSING: begin
                ram_read_en = 1'b1;
                dp_valid_in = 1'b1; // Inyectamos al Datapath
                
                raddr_next = raddr_reg + 1;
                if (raddr_reg == TOTAL_BLOCKS - 1) begin
                    next_state = FLUSHING;
                end
            end

            FLUSHING: begin
                // Ya no leemos más de la RAM, pero esperamos a que la tubería
                // termine de vaciarse (cuando waddr alcance el total de bloques)
                if (waddr_reg == TOTAL_BLOCKS - 1 && dp_valid_out) begin
                    next_state = DONE_STATE;
                end
            end

            DONE_STATE: begin
                done = 1'b1;
                // Esperamos a que baje la señal start para reiniciar
                if (!start) next_state = IDLE; 
            end
        endcase
    end

    // Conexión del puntero de lectura hacia la RAM
    assign ram_read_addr  = raddr_reg;
    // La señal de escritura es directamente el valid_out del Datapath
    assign ram_write_en   = dp_valid_out;
    assign ram_write_addr = waddr_reg;

endmodule