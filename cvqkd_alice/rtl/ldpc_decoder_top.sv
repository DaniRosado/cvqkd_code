`timescale 1ns / 1ps

import bg_rom_pkg::*;

module ldpc_decoder_top #(
    parameter int W = 16,
    parameter int Z = 384,
    parameter int MAX_ITER = 20
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    output logic         done,
    output logic         success,
    input  logic [Z*W-1:0] llr_in_bus,
    input  logic [383:0]   bob_syndrome_in [0:45],
    output logic [Z-1:0]   key_bits_out,
    // Puertos de lectura para depuración (Debug readback)
    input  logic [6:0]     debug_rd_addr,
    output logic [Z-1:0]   debug_rd_data
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_LOAD,
        ST_READ_LAYER,
        ST_READ_DRAIN,
        ST_WRITE_LAYER,
        ST_CHECK,
        ST_DONE
    } state_t;
    state_t state;

    logic [5:0] row_ptr;
    logic [6:0] col_ptr;
    logic [6:0] iter_cnt;
    logic       en_write_p, en_write_r;
    logic       start_row_pulse;
    logic       we_p;

    logic [8:0]  rom_shift;
    logic [6:0]  p_addr;
    logic [11:0] r_addr;
    logic        rom_valid;

    logic [Z*W-1:0] p_data_out, p_data_new;
    logic [Z*W-1:0] r_data_out, r_data_new;

    logic [8:0] rom_shift_q;
    logic       rom_valid_q;
    logic [6:0] col_idx_q;
    logic [6:0] col_idx_valid_q;
    logic [67:0] tb_cols_seen_mask;
    logic [6:0]  tb_cols_seen_count;
    logic [7:0]  tb_col_counts [0:67];
    logic [7:0]  tb_col_max;
    logic [15:0] tb_col_dup_events;
    logic [6:0]  tb_col_idx_seen;

    logic       en_llr_load;
    logic [Z*W-1:0] p_data_new_dp;
    logic [Z-1:0]   row_syndrome;
    logic [Z-1:0]   row_syndrome_p;
    logic [Z-1:0]   q_sign_dbg;

    logic [6:0]  p_wr_addr;
    logic [11:0] r_wr_addr;
    logic [6:0]  p_addr_prev;
    logic [11:0] r_addr_prev;

    // --- Registros de tubería para señales de habilitación de escritura ---
    logic       en_write_p_q;
    logic       en_write_r_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_write_p_q <= 1'b0;
            en_write_r_q <= 1'b0;
        end else begin
            en_write_p_q <= en_write_p;
            en_write_r_q <= en_write_r;
        end
    end

    always_ff @(posedge clk) begin
        p_addr_prev <= p_addr;
        r_addr_prev <= r_addr;
    end

    assign en_llr_load = (state == ST_LOAD);
    assign p_data_new  = en_llr_load ? llr_in_bus : p_data_new_dp;
    
    // Alineación temporal: we_p y direcciones usan las versiones retrasadas en procesamiento de capa
    assign we_p = en_llr_load ? en_write_p : (en_write_p_q && rom_valid_q);
    assign p_wr_addr = en_llr_load ? p_addr : p_addr_prev;
    assign r_wr_addr = r_addr_prev;

    ldpc_rom_controller rom_ctrl (
        .clk(clk),
        .current_row(row_ptr),
        .current_col(col_ptr),
        .shift_val(rom_shift),
        .p_ram_addr(p_addr),
        .r_ram_addr(r_addr),
        .valid_entry(rom_valid)
    );

    always_ff @(posedge clk) begin
        rom_shift_q <= rom_shift;
        rom_valid_q <= rom_valid;
        col_idx_q   <= col_ptr;
        col_idx_valid_q <= col_idx_q;
    end

    // Monitorización de columnas procesadas para la fila 45 (depuración)
    always_ff @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            tb_cols_seen_mask <= '0;
            tb_cols_seen_count <= '0;
            tb_col_max <= '0;
            tb_col_dup_events <= '0;
            for (i = 0; i < 68; i = i + 1) begin
                tb_col_counts[i] <= '0;
            end
        end else if (start_row_pulse && row_ptr == 45) begin
            tb_cols_seen_mask <= '0;
            tb_cols_seen_count <= '0;
            tb_col_max <= '0;
            tb_col_dup_events <= '0;
            for (i = 0; i < 68; i = i + 1) begin
                tb_col_counts[i] <= '0;
            end
        end else if ((state == ST_READ_LAYER || state == ST_READ_DRAIN) && row_ptr == 45 && rom_valid_q) begin
            logic [7:0] next_count;
            tb_col_idx_seen = col_idx_q;
            next_count = tb_col_counts[tb_col_idx_seen] + 1'b1;
            if (!tb_cols_seen_mask[tb_col_idx_seen]) begin
                tb_cols_seen_mask[tb_col_idx_seen] <= 1'b1;
                tb_cols_seen_count <= tb_cols_seen_count + 1'b1;
            end else begin
                tb_col_dup_events <= tb_col_dup_events + 1'b1;
            end
            tb_col_counts[tb_col_idx_seen] <= next_count;
            if (next_count > tb_col_max) begin
                tb_col_max <= next_count;
            end
        end
    end

    // Interfaz de lectura de depuración para el puerto BRAM
    logic [6:0] p_rd_addr;
    assign p_rd_addr = (state == ST_DONE) ? debug_rd_addr : p_addr;

    ldpc_bram_block #(.Z(Z), .W(W), .DEPTH(68)) p_mem (
        .clk(clk),
        .rd_addr(p_rd_addr),
        .wr_addr(p_wr_addr),
        .din(p_data_new),
        .we(we_p),
        .dout(p_data_out)
    );

    ldpc_bram_block #(.Z(Z), .W(W), .DEPTH(46*68)) r_mem (
        .clk(clk),
        .rd_addr(r_addr),
        .wr_addr(r_wr_addr),
        .din(r_data_new),
        .we(en_llr_load ? 1'b0 : (en_write_r_q && rom_valid_q)),
        .dout(r_data_out)
    );

    ldpc_layer_datapath #(.Z(Z), .W(W)) layer_engine (
        .clk(clk),
        .rst_n(rst_n),
        .start_row(start_row_pulse),
        .phase(state == ST_WRITE_LAYER),
        .valid_in(rom_valid && (state == ST_READ_LAYER || state == ST_READ_DRAIN)),
        .col_idx(col_idx_q),
        .shift_val(rom_shift_q),
        .syndrome_row({<<{bob_syndrome_in[row_ptr]}}),
        .p_mem_data(p_data_out),
        .r_mem_data(r_data_out),
        .p_mem_new(p_data_new_dp),
        .r_mem_new(r_data_new),
        .row_syndrome(row_syndrome),
        .row_syndrome_p(row_syndrome_p),
        .q_sign_dbg(q_sign_dbg)
    );

    always_comb begin
        for (int j = 0; j < Z; j++) begin
            key_bits_out[j] = p_data_out[j*W + (W-1)];
            debug_rd_data[j] = p_data_out[j*W + (W-1)];
        end
    end

    logic       row_fail;
    logic [5:0] row_fail_idx;
    logic       row_fail_raw;
    logic       row_fail_rev;
    logic [Z-1:0] row_syndrome_rev;
    assign row_syndrome_rev = {<<{row_syndrome}};
    logic [67:0] valid_seen;
    int         valid_count;

    // --- Máquina de Estados Finita (FSM) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            row_ptr <= 0; col_ptr <= 0; iter_cnt <= 0;
            en_write_p <= 0; en_write_r <= 0;
            start_row_pulse <= 0;
            done <= 0; success <= 0;
            row_fail <= 0;
            row_fail_idx <= 0;
            row_fail_raw <= 0;
            row_fail_rev <= 0;
            valid_seen <= '0;
            valid_count <= 0;
        end else begin
            start_row_pulse <= 0;
            if (start_row_pulse) begin
                valid_seen <= '0;
                valid_count <= 0;
            end else if (rom_valid_q && (state == ST_READ_LAYER || state == ST_READ_DRAIN)) begin
                if (!valid_seen[col_idx_q]) begin
                    valid_seen[col_idx_q] <= 1'b1;
                    valid_count <= valid_count + 1;
                end
            end
            case (state)
                ST_IDLE: begin
                    done <= 0;
                    success <= 0;
                    row_ptr <= 0; col_ptr <= 0; iter_cnt <= 0;
                    row_fail <= 0;
                    row_fail_raw <= 0;
                    row_fail_rev <= 0;
                    row_fail_idx <= 0;
                    valid_seen <= '0;
                    valid_count <= 0;
                    if (start) begin
                        state <= ST_LOAD;
                        en_write_p <= 1;
                    end
                end

                ST_LOAD: begin
                    if (col_ptr == 67) begin
                        col_ptr <= 0;
                        en_write_p <= 0;
                        start_row_pulse <= 1;
                        state <= ST_READ_LAYER;
                    end else begin
                        col_ptr <= col_ptr + 1;
                    end
                end

                ST_READ_LAYER: begin
                    if (col_ptr == 67) begin
                        state <= ST_READ_DRAIN;
                    end else begin
                        col_ptr <= col_ptr + 1;
                    end
                end

                ST_READ_DRAIN: begin
                    col_ptr <= 0;
                    state <= ST_WRITE_LAYER;
                    en_write_p <= 1;
                    en_write_r <= 1;
                end

                ST_WRITE_LAYER: begin
                    if (col_ptr == 67) begin
                        col_ptr <= 0;
                        en_write_p <= 0;
                        en_write_r <= 0;
                        if ((row_syndrome_rev != '0) || $isunknown(row_syndrome_rev)) begin
                            row_fail <= 1;
                            row_fail_idx <= row_ptr;
                            if ($isunknown(row_syndrome_rev)) begin
                                $display("[WARNING] row%0d syndrome has X bits (uninitialized RAM)", row_ptr);
                            end
                        end
                        if (row_ptr == 45 && iter_cnt == 0) begin
                            $display("[DEBUG] row45 valid_count=%0d seen67=%0d", valid_count, valid_seen[67]);
                        end
                        if (row_ptr == 45) begin
                            row_ptr <= 0;
                            state <= ST_CHECK;
                        end else begin
                            row_ptr <= row_ptr + 1;
                            start_row_pulse <= 1;
                            state <= ST_READ_LAYER;
                        end
                    end else begin
                        col_ptr <= col_ptr + 1;
                    end
                end

                ST_CHECK: begin
                    if (row_fail) begin
                        if (iter_cnt == $bits(iter_cnt)'(MAX_ITER - 1)) begin
                            state <= ST_DONE;
                            success <= 0;
                        end else begin
                            iter_cnt <= iter_cnt + 1;
                            row_fail <= 0;
                            start_row_pulse <= 1;
                            state <= ST_READ_LAYER;
                        end
                    end else begin
                        state <= ST_DONE;
                        success <= 1;
                    end
                end

                ST_DONE: begin
                    done <= 1;
                    if (start) begin
                        state <= ST_IDLE;
                        done <= 0;
                        success <= 0;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule