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
    input  logic       is_pass1,
    
    // --- Interfaces con las BRAM ---
    input  logic [BUS_WIDTH-1:0] p_read_data_flat,
    input  logic [BUS_WIDTH-1:0] r_read_data_flat,
    output logic [BUS_WIDTH-1:0] p_write_data_flat,
    output logic [BUS_WIDTH-1:0] r_write_data_flat,
    
    // --- Síndrome ---
    output logic [Z-1:0]         cn_signs_out,
    input  logic [Z-1:0]         target_syn_row,

    // --- Control del acumulador de síndrome (Pasada 1) ---
    input  logic                 syn_valid,
    input  logic                 syn_start_row
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
    // FASE 2: ROTACIÓN DE SIGNO L_q (1 bit por Z, Pasada 1)
    // ==========================================
    // Para reconstruir R_new en Pasada 1, solo se necesita el signo rotado de L_q.
    // Un shifter de 384x1 bits consume apenas ~1.7k LUTs (en lugar de 15.5k de un shifter de 8 bits).
    logic [0:0] L_q_sign         [0:Z-1];
    logic [0:0] L_q_sign_shifted [0:Z-1];
    logic       L_q_sign_reg     [0:Z-1];

    always_comb begin
        for (int i = 0; i < Z; i++) begin
            L_q_sign[i] = L_q_reg[i][7];
        end
    end

    barrel_shifter #(.Z(Z), .W(1)) shifter_lq_sign (
        .data_in    (L_q_sign),
        .shift_val  (shift_pipe[1]), // Sincronizado al Ciclo 2
        .dir_inverse(1'b1),          // Izquierda
        .data_out   (L_q_sign_shifted)
    );

    always_ff @(posedge clk) begin
        for (int i = 0; i < Z; i++) begin
            L_q_sign_reg[i] <= L_q_sign_shifted[i][0];
        end
    end

    // ==========================================
    // FASE 3: CNU Array (Serial)
    // ==========================================
    logic [6:0] min1     [0:Z-1];
    logic [6:0] min2     [0:Z-1];
    logic [6:0] min1_col [0:Z-1];
    logic       tot_sign [0:Z-1];
    logic [W-1:0] L_q_shifted_reg [0:Z-1];

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

    // ==========================================
    // FASE 4: Reconstrucción (R_new en dominio CNU)
    // ==========================================
    // Selección del mínimo primero y un único escalado x0.75, ahorrando 384 restadores de 7 bits
    logic [W-1:0] R_new_cnu_order [0:Z-1];
    
    always_comb begin
        for (int i = 0; i < Z; i++) begin
            logic msg_sign;
            logic [6:0] raw_min;
            logic [6:0] scaled_min;

            msg_sign = tot_sign[i] ^ L_q_sign_reg[i] ^ target_syn_row[i];
            
            if (col_pipe[2] == min1_col[i]) begin
                raw_min = min2[i];
            end else begin
                raw_min = min1[i];
            end

            scaled_min = raw_min - (raw_min >> 2);
            R_new_cnu_order[i] = {msg_sign, scaled_min};
        end
    end

    // ==========================================
    // FASE 2 y 5: BARREL SHIFTER COMPARTIDO (Directo 8b en Pasada 0, Inverso 8b en Pasada 1)
    // ==========================================
    // Como en Pasada 0 solo se rota L_q hacia la CNU y en Pasada 1 solo se rota R_new
    // hacia la VNU (mientras que el signo de L_q se rota concurrentemente en 1 bit con shifter_lq_sign),
    // el shifter de 8 bits se multiplexa limpiamente, ahorrando más de 15.000 LUTs.
    logic [W-1:0] bs_in   [0:Z-1];
    logic [8:0]   bs_shift;
    logic         bs_dir;
    logic [W-1:0] bs_out  [0:Z-1];

    always_comb begin
        if (is_pass1 == 1'b0) begin
            // Pasada 0: VNU -> CNU (Rotación Directa a la izquierda, shift_pipe[1])
            bs_in    = L_q_reg;
            bs_shift = shift_pipe[1];
            bs_dir   = 1'b1;
        end else begin
            // Pasada 1: CNU -> VNU (Rotación Inversa a la derecha, shift_pipe[2])
            bs_in    = R_new_cnu_order;
            bs_shift = shift_pipe[2];
            bs_dir   = 1'b0;
        end
    end

    barrel_shifter #(.Z(Z), .W(W)) shared_shifter (
        .data_in    (bs_in),
        .shift_val  (bs_shift),
        .dir_inverse(bs_dir),
        .data_out   (bs_out)
    );

    // En Pasada 0, capturamos la salida para alimentar el array de CNUs
    always_ff @(posedge clk) begin
        if (!is_pass1) begin
            L_q_shifted_reg <= bs_out;
        end
    end

    // En Pasada 1, la salida alimenta R_new hacia VNU y R_BRAM
    assign R_new = bs_out;

    // ==========================================
    // ACUMULADOR DE SÍNDROME (Hard-decision sobre L_write, W=1)
    // ==========================================
    // Rotamos únicamente el bit de signo (384 x 1 bit) en lugar de 384 x 8 bits
    logic [Z-1:0] syn_accum;
    logic [0:0]   L_write_sign         [0:Z-1];
    logic [0:0]   L_write_sign_shifted [0:Z-1];

    always_comb begin
        for (int i = 0; i < Z; i++) begin
            L_write_sign[i] = L_write[i][7];
        end
    end

    barrel_shifter #(.Z(Z), .W(1)) shifter_syndrome (
        .data_in    (L_write_sign),
        .shift_val  (shift_pipe[2]),
        .dir_inverse(1'b1),
        .data_out   (L_write_sign_shifted)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            syn_accum <= '0;
        end else if (syn_valid) begin
            if (syn_start_row) begin
                for (int i = 0; i < Z; i++) begin
                    syn_accum[i] <= L_write_sign_shifted[i][0];
                end
            end else begin
                for (int i = 0; i < Z; i++) begin
                    syn_accum[i] <= syn_accum[i] ^ L_write_sign_shifted[i][0];
                end
            end
        end
    end

    assign cn_signs_out = syn_accum;

endmodule