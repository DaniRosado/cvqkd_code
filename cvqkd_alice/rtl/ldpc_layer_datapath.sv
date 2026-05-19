`timescale 1ns / 1ps

module ldpc_layer_datapath #(
    parameter int Z = 384,
    parameter int W = 8
)(
    input  logic              clk,
    input  logic              rst_n,
    input  logic              start_row,
    input  logic              phase,
    input  logic              valid_in,
    input  logic [6:0]        col_idx,
    input  logic [8:0]        shift_val,
    input  logic [Z-1:0]      syndrome_row,
    input  logic [Z*W-1:0]    p_mem_data,
    input  logic [Z*W-1:0]    r_mem_data,
    output logic [Z*W-1:0]    p_mem_new,
    output logic [Z*W-1:0]    r_mem_new,
    output logic [Z-1:0]      row_syndrome,
    output logic [Z-1:0]      row_syndrome_p,
    output logic [Z-1:0]      q_sign_dbg
);
    logic [Z*W-1:0] p_shifted;
    logic [Z*W-1:0] r_old_shifted;

    barrel_shifter_word #(.Z(Z), .W(W)) fwd_shifter_p (
        .data_in(p_mem_data),
        .shift_val(shift_val),
        .data_out(p_shifted)
    );
    barrel_shifter_word #(.Z(Z), .W(W)) fwd_shifter_r (
        .data_in(r_mem_data),
        .shift_val(shift_val),
        .data_out(r_old_shifted)
    );
    logic [Z*W-1:0] vnu_to_cnu_bus;
    logic [Z*W-1:0] vnu_to_cnu_bus_q;
    logic [Z*W-1:0] cnu_to_vnu_bus;
    logic [Z*W-1:0] p_new_parallel;

    genvar i;
    generate
        for (i = 0; i < Z; i++) begin : gen_nodes
            vnu_processor #(.W(W)) vnu_inst (
                .clk(clk),
                .rst_n(rst_n),
                .p_n_in(p_shifted[i*W +: W]),
                .r_old_in(r_old_shifted[i*W +: W]),
                .r_new_in(cnu_to_vnu_bus[i*W +: W]),
                .q_mn_out(vnu_to_cnu_bus[i*W +: W]),
                .p_n_out(p_new_parallel[i*W +: W]),
                .hard_decision()
            );
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vnu_to_cnu_bus_q <= '0;
        end else begin
            vnu_to_cnu_bus_q <= vnu_to_cnu_bus;
        end
    end

    generate
        for (i = 0; i < Z; i++) begin : gen_qsign_dbg
            assign q_sign_dbg[i] = vnu_to_cnu_bus_q[i*W + (W-1)];
        end
    endgenerate

    cnu_min_sum_array #(.Z(Z), .W(W), .COL_W(7)) cnu_array (
        .clk(clk),
        .rst_n(rst_n),
        .start_row(start_row),
        .phase(phase),
        .valid_in(valid_in),
        // CORRECCIÓN 1: Se usa el bus combinacional para alinear los tiempos
        .q_bus(vnu_to_cnu_bus),         
        .q_bus_current(vnu_to_cnu_bus),
        .p_bus(p_shifted),
        .col_idx(col_idx),
        .syndrome_row(syndrome_row),
        .r_new_bus(cnu_to_vnu_bus),
        .row_syndrome(row_syndrome),
        .row_syndrome_p(row_syndrome_p)
    );

    // Reverse shift: forward uses (i + shift) % Z (upward rotation),
    // so reverse uses (i - shift) mod Z = (i + Z - shift) % Z (downward).
    logic [8:0] inv_shift_val;
    
    // CORRECCIÓN 2: Si el shift original era 0, el inverso debe ser 0 obligatoriamente
    assign inv_shift_val = (shift_val == 0) ? 9'd0 : 9'(Z) - shift_val;

    barrel_shifter_word #(.Z(Z), .W(W)) rev_shifter_p (
        .data_in(p_new_parallel),
        .shift_val(inv_shift_val),
        .data_out(p_mem_new)
    );
    barrel_shifter_word #(.Z(Z), .W(W)) rev_shifter_r (
        .data_in(cnu_to_vnu_bus),
        .shift_val(inv_shift_val),
        .data_out(r_mem_new)
    );
endmodule