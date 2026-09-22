`timescale 1ns / 1ps
import bg1_rom_pkg::*;

module ldpc_controller_fsm #(
    parameter int PIPELINE_DEPTH = 2,
    parameter int MAX_ITER = 200
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start_decoding,
    
    output logic [6:0] p_read_addr, // addr de la memoria de L
    output logic [8:0] r_read_addr, // addr de la memoria de R
    output logic       p_write_en,
    output logic [6:0] p_write_addr,
    output logic       r_write_en,
    output logic [8:0] r_write_addr,
    
    output logic       datapath_valid_in,
    output logic       datapath_start_row,
    output logic [6:0] datapath_col_idx,
    output logic [8:0] datapath_shift,
    
    output logic [5:0] current_row_idx,
    output logic       iter_start,
    output logic       row_done,
    input  logic       is_converged,
    
    output logic       decoding_done,
    output logic       decoding_success
);

    typedef enum logic [2:0] {
        IDLE, INIT_ITER, PROCESS_ROW, WAIT_PIPELINE, CHECK_SYNDROME, DONE
    } state_t;
    
    state_t state, next_state;

    logic [5:0] row_idx, next_row_idx;
    logic [5:0] edge_counter, next_edge_counter;
    logic [7:0] iter_counter, next_iter_counter;
    logic [3:0] wait_counter, next_wait_counter;
    
    // Bandera de Doble Pasaje (0 = Calculando Mínimos, 1 = Escribiendo Resultados)
    logic pass_flag, next_pass_flag; 
    
    row_info_t  current_row_info;
    edge_info_t current_edge;
    logic [8:0] current_rom_ptr;
    logic       valid_read_cycle;

    assign current_row_info = ROW_INFO_ROM[row_idx];
    assign current_rom_ptr  = current_row_info.start_ptr + edge_counter;
    assign current_edge     = EDGE_ROM[current_rom_ptr];
    assign current_row_idx  = row_idx;

    logic [6:0] p_addr_pipe [0:PIPELINE_DEPTH-1];
    logic [8:0] r_addr_pipe [0:PIPELINE_DEPTH-1];
    logic       valid_pipe  [0:PIPELINE_DEPTH-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i=0; i<PIPELINE_DEPTH; i++) valid_pipe[i] <= 1'b0;
        end else begin
            p_addr_pipe[0] <= current_edge.col_idx;
            r_addr_pipe[0] <= current_rom_ptr;
            valid_pipe[0]  <= valid_read_cycle;

            for (int i=1; i<PIPELINE_DEPTH; i++) begin
                p_addr_pipe[i] <= p_addr_pipe[i-1];
                r_addr_pipe[i] <= r_addr_pipe[i-1];
                valid_pipe[i]  <= valid_pipe[i-1];
            end
        end
    end

    // --- Lógica de Control Dinámico ---
    assign p_read_addr        = current_edge.col_idx;
    assign r_read_addr        = current_rom_ptr;
    assign datapath_shift     = current_edge.shift_val;
    assign datapath_col_idx   = current_edge.col_idx;
    
    // La CNU solo lee datos nuevos (y se resetea) en la Pasada 0
    assign datapath_valid_in  = valid_read_cycle & ~pass_flag;
    assign datapath_start_row = (edge_counter == 0) && valid_read_cycle && ~pass_flag;

    // Solo habilitamos la escritura en memoria en la Pasada 1
    assign p_write_en   = valid_pipe[PIPELINE_DEPTH-1] & pass_flag;
    assign p_write_addr = p_addr_pipe[PIPELINE_DEPTH-1];
    assign r_write_en   = valid_pipe[PIPELINE_DEPTH-1] & pass_flag;
    assign r_write_addr = r_addr_pipe[PIPELINE_DEPTH-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            row_idx      <= 0;
            edge_counter <= 0;
            iter_counter <= 0;
            wait_counter <= 0;
            pass_flag    <= 0;
        end else begin
            state        <= next_state;
            row_idx      <= next_row_idx;
            edge_counter <= next_edge_counter;
            iter_counter <= next_iter_counter;
            wait_counter <= next_wait_counter;
            pass_flag    <= next_pass_flag;
        end
    end

    always_comb begin
        next_state        = state;
        next_row_idx      = row_idx;
        next_edge_counter = edge_counter;
        next_iter_counter = iter_counter;
        next_wait_counter = wait_counter;
        next_pass_flag    = pass_flag;
        
        valid_read_cycle  = 1'b0;
        iter_start        = 1'b0;
        row_done          = 1'b0;
        decoding_done     = 1'b0;
        decoding_success  = 1'b0;

        case (state)
            IDLE: begin
                next_row_idx      = 0;
                next_edge_counter = 0;
                next_iter_counter = 0;
                next_pass_flag    = 0;
                if (start_decoding) next_state = INIT_ITER;
            end

            INIT_ITER: begin
                iter_start = 1'b1;
                next_state = PROCESS_ROW;
            end

            PROCESS_ROW: begin
                valid_read_cycle = 1'b1;
                if (edge_counter == current_row_info.num_edges - 1) begin
                    next_edge_counter = 0;
                    next_wait_counter = 0;
                    next_state = WAIT_PIPELINE;
                end else begin
                    next_edge_counter = edge_counter + 1;
                end
            end

            WAIT_PIPELINE: begin
                // Añadimos el +1 para forzar ese ciclo de reloj extra
                if (wait_counter == PIPELINE_DEPTH + 1) begin
                    if (pass_flag == 1'b0) begin
                        // Terminamos Pasada 0. Empezamos Pasada 1 (Escritura)
                        next_pass_flag = 1'b1;
                        next_state = PROCESS_ROW;
                    end else begin
                        // Terminamos Pasada 1. Fila completa.
                        row_done = 1'b1;
                        next_pass_flag = 1'b0;
                        if (row_idx == 45) begin
                            next_state = CHECK_SYNDROME;
                        end else begin
                            next_row_idx = row_idx + 1;
                            next_state   = PROCESS_ROW;
                        end
                    end
                end else begin
                    next_wait_counter = wait_counter + 1;
                end
            end

            CHECK_SYNDROME: begin
                if (is_converged) begin
                    next_state = DONE;
                end else begin
                    if (iter_counter == MAX_ITER - 1) begin
                        next_state = DONE; 
                    end else begin
                        next_iter_counter = iter_counter + 1;
                        next_row_idx      = 0;
                        next_state        = INIT_ITER;
                    end
                end
            end

            DONE: begin
                decoding_done = 1'b1;
                if (is_converged) decoding_success = 1'b1;
                next_state = IDLE;
            end
        endcase
    end
endmodule