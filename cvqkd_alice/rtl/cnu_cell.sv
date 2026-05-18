`timescale 1ns / 1ps

module cnu_cell #(
    parameter int W = 8,
    parameter int COL_W = 7
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start_row,
    input  logic         phase,
    input  logic         valid_in,
    input  logic         q_sign,
    input  logic         p_sign,
    input  logic [W-2:0] q_mag,
    input  logic [COL_W-1:0] col_idx,
    input  logic         syndrome_bit,
    input  logic         target_syndrome_bit,
    output logic [W-2:0] min1,
    output logic [W-2:0] min2,
    output logic [COL_W-1:0] min1_idx,
    output logic         total_sign_q,
    output logic         total_sign_p
);

    localparam logic [W-2:0] MAX_MAG = '1;

    logic [W-2:0]     reg_min1;
    logic [W-2:0]     reg_min2;
    logic [COL_W-1:0] reg_min1_idx;
    logic             reg_total_sign_q;
    logic             reg_total_sign_p;
    logic             debug_min1_updated;

    assign min1       = reg_min1;
    assign min2       = reg_min2;
    assign min1_idx   = reg_min1_idx;
    assign total_sign_q = reg_total_sign_q;
    assign total_sign_p = reg_total_sign_p;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_min1       <= MAX_MAG;
            reg_min2       <= MAX_MAG;
            reg_min1_idx   <= '0;
            reg_total_sign_q <= 1'b0;
            reg_total_sign_p <= 1'b0;
        end else begin
            if (start_row) begin
                reg_min1       <= MAX_MAG;
                reg_min2       <= MAX_MAG;
                reg_min1_idx   <= '0;
                reg_total_sign_q <= target_syndrome_bit;
                reg_total_sign_p <= target_syndrome_bit;
            end else if (valid_in && !phase) begin
                reg_total_sign_q <= reg_total_sign_q ^ q_sign;
                reg_total_sign_p <= reg_total_sign_p ^ p_sign;
                if (q_mag < reg_min1) begin
                    reg_min2     <= reg_min1;
                    reg_min1     <= q_mag;
                    reg_min1_idx <= col_idx;
                    debug_min1_updated <= 1'b1;
                end else if (q_mag < reg_min2) begin
                    reg_min2 <= q_mag;
                end
            end else begin
                debug_min1_updated <= 1'b0;
            end
        end
    end

endmodule
