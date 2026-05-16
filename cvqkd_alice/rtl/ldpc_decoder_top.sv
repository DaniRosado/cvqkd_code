`timescale 1ns / 1ps

import bg_rom_pkg::*;

module ldpc_decoder_top #(
    parameter int W = 8,
    parameter int Z = 384,
    parameter int MAX_ITER = 20
)(
    input  logic         clk,
    input  logic         rst_n,
    
    // Control
    input  logic         start,
    output logic         done,
    output logic         success,
    
    // Datos (LLRs desde MDR y Síndrome de Bob)
    input  logic [Z*W-1:0] llr_in_bus, 
    input  logic [383:0]   bob_syndrome_in [0:45],
    
    // Salida
    output logic [Z-1:0]   key_bits_out 
);

    // =========================================================================
    // 1. SEÑALES DE INTERCONEXIÓN (LOS CABLES)
    // =========================================================================
    // Control de la FSM
    logic [5:0] row_ptr;
    logic [6:0] col_ptr;
    logic [4:0] iter_count;
    logic       en_write_p, en_write_r;
    
    // Salidas del ROM Controller
    logic [8:0]  rom_shift;
    logic [6:0]  p_addr;
    logic [11:0] r_addr;
    logic        rom_valid;
    
    // Datos desde/hacia BRAMs
    logic [Z*W-1:0] p_data_out, p_data_new;
    logic [Z*W-1:0] r_data_out, r_data_new;
    
    // Señales retardadas (Pipeline) para sincronizar con la latencia de la BRAM
    logic [8:0] rom_shift_q;
    logic       rom_valid_q;
    
    // Señal de carga inicial de LLRs y mux para el dato de entrada a la P-mem
    logic       en_llr_load;
    logic [Z*W-1:0] p_data_new_dp;   // Salida del datapath (sin muxear)
    
    // Durante ST_LOAD escribimos los LLRs de entrada directamente; en otro caso usamos el datapath
    assign en_llr_load = (state == ST_LOAD);
    assign p_data_new  = en_llr_load ? llr_in_bus : p_data_new_dp;
    
    // Señal de write-enable para la P-mem: durante ST_LOAD escribimos siempre,
    // en modo normal solo cuando la entrada ROM es válida
    logic we_p;
    assign we_p = en_llr_load ? en_write_p : (en_write_p && rom_valid_q);

    // =========================================================================
    // 2. INSTANCIACIÓN DE BLOQUES DE CONTROL
    // =========================================================================
    
    // Controlador de la Matriz BG1
    ldpc_rom_controller rom_ctrl (
        .clk(clk),
        .current_row(row_ptr),
        .current_col(col_ptr),
        .shift_val(rom_shift),
        .p_ram_addr(p_addr),
        .r_ram_addr(r_addr),
        .valid_entry(rom_valid)
    );

    // Retardo de señales de control (1 ciclo) para esperar a la BRAM
    always_ff @(posedge clk) begin
        rom_shift_q <= rom_shift;
        rom_valid_q <= rom_valid;
    end

    // =========================================================================
    // 3. INSTANCIACIÓN DE MEMORIAS (BRAM)
    // =========================================================================
    
    // Memoria de LLRs Totales (P)
    ldpc_bram_block #(.DEPTH(68)) p_mem (
        .clk(clk),
        .addr_a(p_addr),
        .din_a(p_data_new),
        .we_a(we_p), // Durante ST_LOAD escribe siempre; en modo normal solo si ROM válida
        .dout_a(p_data_out),
        .addr_b(col_ptr), // Puerto B para extracción de bits finales
        .dout_b() 
    );

    // Memoria de Mensajes (R)
    ldpc_bram_block #(.DEPTH(46*68)) r_mem (
        .clk(clk),
        .addr_a(r_addr),
        .din_a(r_data_new),
        .we_a(en_write_r && rom_valid_q),
        .dout_a(r_data_out),
        .addr_b(),
        .dout_b()
    );

    // =========================================================================
    // 4. INSTANCIACIÓN DEL DATAPATH (PROCESAMIENTO)
    // =========================================================================
    
    ldpc_layer_datapath #(.Z(Z), .W(W)) layer_engine (
        .clk(clk),
        .rst_n(rst_n),
        .shift_val(rom_shift_q), // Valor sincronizado con el dato de la BRAM
        .cnu_vnu_ctrl(1'b1),     // Simplificado: modo actualización
        .p_mem_data(p_data_out),
        .r_mem_data(r_data_out),
        .p_mem_new(p_data_new_dp),
        .r_mem_new(r_data_new)
    );

    // =========================================================================
    // 5. LÓGICA DE SALIDA Y HARD DECISION
    // =========================================================================
    // Extraemos el bit de signo de cada LLR de la memoria P para la clave final
    always_comb begin
        for (int j = 0; j < Z; j++) begin
            // Si el LLR es negativo (MSB=1), el bit es 1.
            key_bits_out[j] = p_data_out[j*W + (W-1)];
        end
    end

    // Aquí iría tu FSM principal que gestiona row_ptr, col_ptr y las banderas
    // (Utilizando el esqueleto que diseñamos anteriormente)
    // --- Estados de la FSM ---
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_LOAD,      // Carga inicial de LLRs
        ST_READ_LAYER, // Fase 1: Leer fila y calcular mínimos en CNUs
        ST_WRITE_LAYER,// Fase 2: Escribir nuevos LLRs y mensajes R
        ST_CHECK,     // Verificar síndrome (Early Termination)
        ST_DONE
    } state_t;

    state_t state;
    logic [4:0] iter_cnt;
    logic       start_row_pulse;

    // --- Lógica de la FSM y Control de Punteros ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            row_ptr <= 0; col_ptr <= 0; iter_cnt <= 0;
            en_write_p <= 0; en_write_r <= 0;
            start_row_pulse <= 0;
            done <= 0; success <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    done <= 0; success <= 0;
                    if (start) state <= ST_LOAD;
                end

                ST_LOAD: begin
                    // Cargamos las 68 columnas de LLRs desde el bus de entrada
                    en_write_p <= 1;
                    if (col_ptr == 67) begin
                        col_ptr <= 0;
                        en_write_p <= 0;
                        state <= ST_READ_LAYER;
                    end else col_ptr <= col_ptr + 1;
                end

                ST_READ_LAYER: begin
                    start_row_pulse <= (col_ptr == 0);
                    // Recorremos columnas para alimentar las CNUs
                    if (col_ptr == 67) begin
                        col_ptr <= 0;
                        state <= ST_WRITE_LAYER;
                    end else col_ptr <= col_ptr + 1;
                end

                ST_WRITE_LAYER: begin
                    en_write_p <= 1; en_write_r <= 1;
                    if (col_ptr == 67) begin
                        col_ptr <= 0;
                        if (row_ptr == 45) begin
                            row_ptr <= 0;
                            state <= ST_CHECK;
                        end else begin
                            row_ptr <= row_ptr + 1;
                            state <= ST_READ_LAYER;
                        end
                    end else col_ptr <= col_ptr + 1;
                end

                ST_CHECK: begin
                    en_write_p <= 0; en_write_r <= 0;
                    // Aquí iría la lógica de comparación con bob_syndrome_in
                    if (iter_cnt == 5'(MAX_ITER - 1)) state <= ST_DONE;
                    else begin
                        iter_cnt <= iter_cnt + 1;
                        state <= ST_READ_LAYER;
                    end
                end

                ST_DONE: begin
                    done <= 1;
                    success <= 1; // Convergió (o alcanzó MAX_ITER sin error)
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule