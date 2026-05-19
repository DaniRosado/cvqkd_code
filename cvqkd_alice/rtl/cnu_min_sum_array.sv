`timescale 1ns / 1ps

module cnu_min_sum_array #(
    parameter int Z = 384,
    parameter int W = 8,
    parameter int COL_W = 7
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start_row,
    input  logic         phase,
    input  logic         valid_in,
    input  logic [Z*W-1:0] q_bus,        // registered VNU output (for accumulation timing)
    input  logic [Z*W-1:0] q_bus_current, // combinatorial VNU output (for r_new sign, matches current column)
    input  logic [Z*W-1:0] p_bus,
    input  logic [COL_W-1:0] col_idx,
    input  logic [Z-1:0]   syndrome_row,
    output logic [Z*W-1:0] r_new_bus,
    output logic [Z-1:0]   row_syndrome,
    output logic [Z-1:0]   row_syndrome_p
);

    logic [W-2:0]     min1_arr [0:Z-1];
    logic [W-2:0]     min2_arr [0:Z-1];
    logic [COL_W-1:0] min1_idx_arr [0:Z-1];
    logic             total_sign_arr [0:Z-1];
    logic             total_sign_p_arr [0:Z-1];

    genvar i;
    generate
        for (i = 0; i < Z; i++) begin : gen_cnu
            cnu_cell #(.W(W), .COL_W(COL_W)) cnu_inst (
                .clk(clk),
                .rst_n(rst_n),
                .start_row(start_row),
                .phase(phase),
                .valid_in(valid_in),
                .q_sign(q_bus[i*W + (W-1)]),
                .p_sign(p_bus[i*W + (W-1)]),
                .q_mag(q_bus[i*W +: (W-1)]),
                .col_idx(col_idx),
                .target_syndrome_bit(syndrome_row[i]),
                .min1(min1_arr[i]),
                .min2(min2_arr[i]),
                .min1_idx(min1_idx_arr[i]),
                .total_sign_q(total_sign_arr[i]),
                .total_sign_p(total_sign_p_arr[i])
            );

            assign row_syndrome[i] = total_sign_arr[i];
            assign row_syndrome_p[i] = total_sign_p_arr[i];

            logic [W-2:0] raw_mag, norm_mag;
            assign raw_mag = (col_idx == min1_idx_arr[i]) ? min2_arr[i] : min1_arr[i];
            // Scaled Min-Sum with alpha=0.75: norm_mag = raw_mag - (raw_mag >> 2).
            // This scaling matches MATLAB convergence behavior at high V_A.
            assign norm_mag = raw_mag - (raw_mag >> 2);

            // During WRITE (phase=1), use registered q_bus to break combinatorial loop
            // between VNU→CNU→VNU. During READ (phase=0), use q_bus_current for correct column timing.
            logic q_sign_for_r;
            assign q_sign_for_r = phase ? q_bus[i*W + (W-1)] : q_bus_current[i*W + (W-1)];

            assign r_new_bus[i*W +: W] = {
                total_sign_arr[i] ^ q_sign_for_r,
                norm_mag
            };
        end
    endgenerate

    `ifdef SIMULATION
    logic [W-2:0] debug_min1_q;
    logic [W-2:0] debug_min2_q;
    logic [COL_W-1:0] debug_min1_idx_q;
    logic debug_valid_q;

    always_ff @(posedge clk) begin
        debug_min1_q <= min1_arr[0];
        debug_min2_q <= min2_arr[0];
        debug_min1_idx_q <= min1_idx_arr[0];
        debug_valid_q <= valid_in;
    end

    always_ff @(posedge clk) begin
        if (start_row)
            $display("[CNU_DBG] start_row: resetting node 0");
        else if (valid_in)
            $display("[CNU_DBG] col=%0d: min1=%d min2=%d min1_idx=%0d",
                     col_idx, min1_arr[0], min2_arr[0], min1_idx_arr[0]);
        else if (phase)
            $display("[CNU_DBG] WRITE: min1=%d min2=%d min1_idx=%0d",
                     min1_arr[0], min2_arr[0], min1_idx_arr[0]);
    end
    `endif

endmodule
