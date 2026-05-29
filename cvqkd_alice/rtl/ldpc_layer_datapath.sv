`timescale 1ns / 1ps

module ldpc_layer_datapath #(
    parameter int Z = 384,
    parameter int W = 8,
    parameter int BUS_WIDTH = Z * W
)(
    input  logic clk,
    input  logic rst_n,
    
    // --- Control desde la FSM ---
    input  logic       valid_in,
    input  logic       start_row,
    input  logic [6:0] col_idx_in,
    input  logic [8:0] shift_val,
    
    // --- Interfaces con las BRAM ---
    input  logic [BUS_WIDTH-1:0] p_read_data_flat,
    input  logic [BUS_WIDTH-1:0] r_read_data_flat,
    output logic [BUS_WIDTH-1:0] p_write_data_flat,
    output logic [BUS_WIDTH-1:0] r_write_data_flat,
    
    // --- Síndrome ---
    output logic [Z-1:0]         cn_signs_out,
    input  logic [Z-1:0]         target_syn_row
);

    // ==========================================
    // 0. Desempaquetado de Buses
    // ==========================================
    logic [W-1:0] L_read [0:Z-1];
    logic [W-1:0] R_old  [0:Z-1];
    logic [W-1:0] L_write[0:Z-1];
    logic [W-1:0] R_new  [0:Z-1];
    
    always_comb begin
        for (int i = 0; i < Z; i++) begin
            L_read[i] = p_read_data_flat[i*W +: W];
            R_old[i]  = r_read_data_flat[i*W +: W];
            p_write_data_flat[i*W +: W] = L_write[i];
            r_write_data_flat[i*W +: W] = R_new[i];
        end
    end

    // ==========================================
    // PIPELINE DE CONTROL Y DESPLAZAMIENTO
    // ==========================================
    logic       valid_pipe [0:2];
    logic       start_pipe [0:2];
    logic [6:0] col_pipe   [0:2];
    logic [8:0] shift_pipe [0:2]; // EL SALVAVIDAS: El pipeline de rotación

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= '{default: 0};
            start_pipe <= '{default: 0};
            col_pipe   <= '{default: 0};
            shift_pipe <= '{default: 0};
        end else begin
            // Stage 0
            valid_pipe[0] <= valid_in;
            start_pipe[0] <= start_row;
            col_pipe[0]   <= col_idx_in;
            shift_pipe[0] <= shift_val;
            
            // Stage 1
            valid_pipe[1] <= valid_pipe[0];
            start_pipe[1] <= start_pipe[0];
            col_pipe[1]   <= col_pipe[0];
            shift_pipe[1] <= shift_pipe[0];

            // Stage 2
            valid_pipe[2] <= valid_pipe[1];
            start_pipe[2] <= start_pipe[1];
            col_pipe[2]   <= col_pipe[1];
            shift_pipe[2] <= shift_pipe[1];
        end
    end

    // ==========================================
    // FASE 1: VNU 
    // ==========================================
    logic [W-1:0] L_q_comb [0:Z-1];
    logic [W-1:0] L_q_reg  [0:Z-1]; 
    logic [W-1:0] L_q_reg2 [0:Z-1];

    generate
        for (genvar i = 0; i < Z; i++) begin : gen_vnu_fase1
            vnu_node vnu_inst (
                .L_read     (L_read[i]),
                .R_old      (R_old[i]),
                .L_q        (L_q_comb[i]),
                .L_q_delayed(L_q_reg2[i]),
                .R_new      (R_new[i]),
                .L_write    (L_write[i])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        L_q_reg  <= L_q_comb;
        L_q_reg2 <= L_q_reg; 
    end

    // ==========================================
    // FASE 2: Barrel Shifter Directo
    // ==========================================
    logic [W-1:0] L_q_shifted_comb [0:Z-1];
    logic [W-1:0] L_q_shifted_reg  [0:Z-1]; 
    
    barrel_shifter #(.Z(Z), .W(W)) shifter_direct (
        .data_in    (L_q_reg),
        .shift_val  (shift_pipe[1]), // Sincronizado al Ciclo 2
        .dir_inverse(1'b1),
        .data_out   (L_q_shifted_comb)
    );

    always_ff @(posedge clk) begin
        L_q_shifted_reg <= L_q_shifted_comb;
    end

    // ==========================================
    // FASE 3: CNU Array (Serial)
    // ==========================================
    logic [6:0] min1     [0:Z-1];
    logic [6:0] min2     [0:Z-1];
    logic [6:0] min1_col [0:Z-1];
    logic       tot_sign [0:Z-1];
    
    generate
        for (genvar i = 0; i < Z; i++) begin : gen_cnu
            cnu_serial_node cnu_inst (
                .clk           (clk),
                .rst_n         (rst_n),
                .start_row     (start_pipe[2]),
                .valid_in      (valid_pipe[2]),
                .col_idx_in    (col_pipe[2]),
                .L_q_in        (L_q_shifted_reg[i]),
                .min1_out      (min1[i]),
                .min2_out      (min2[i]),
                .min1_col_out  (min1_col[i]),
                .total_sign_out(tot_sign[i])
            );
        end
    endgenerate

    always_comb begin
        for (int i = 0; i < Z; i++) begin
            cn_signs_out[i] = tot_sign[i];
        end
    end

    // ==========================================
    // FASE 4: Reconstrucción (R_new)
    // ==========================================
    logic [W-1:0] R_new_cnu_order [0:Z-1];
    
    always_comb begin
        for (int i = 0; i < Z; i++) begin
            logic msg_sign;
            msg_sign = tot_sign[i] ^ L_q_shifted_reg[i][7] ^ target_syn_row[i];
            
            if (col_pipe[2] == min1_col[i]) begin
                R_new_cnu_order[i] = {msg_sign, min2[i]};
            end else begin
                R_new_cnu_order[i] = {msg_sign, min1[i]};
            end
        end
    end

    // ==========================================
    // FASE 5: Barrel Shifter Inverso
    // ==========================================
    barrel_shifter #(.Z(Z), .W(W)) shifter_inverso (
        .data_in    (R_new_cnu_order),
        .shift_val  (shift_pipe[2]), // Sincronizado al Ciclo 3
        .dir_inverse(1'b0),
        .data_out   (R_new)
    );

endmodule