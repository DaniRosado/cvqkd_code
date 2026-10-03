`timescale 1ns / 1ps

// =============================================================================
// Síndrome LDPC de Bob: s_r = XOR de las columnas u_c rotadas de cada arista de
// la fila r del base graph BG1 (Z = 384, 316 aristas, 46 filas).
//
// Las aristas de EDGE_ROM están ordenadas por filas, así que basta un único
// acumulador de 384 bits: se lee una arista por ciclo y cada fila sale en cuanto
// se acumula su última arista. Unos 320 ciclos por síndrome.
//
// Tubería: ciclo t   -> dirección de la columna (u_addr) de la arista t
//          ciclo t+1 -> llega u_data_in (BRAM de 1 ciclo), se rota y se acumula
// =============================================================================

import bg1_rom_pkg::*;

module syndrome_calc_bg1 (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,

    // Interfaz de lectura hacia la RAM de bits U de Bob (latencia de 1 ciclo)
    output logic [6:0]   u_addr,      // Columna del base graph (0 a 67)
    input  logic [383:0] u_data_in,

    // Salida streaming (1 fila por pulso)
    output logic         done,
    output logic         syndrome_valid,
    output logic [5:0]   syndrome_row_idx,
    output logic [383:0] syndrome_data
);

    localparam int TOTAL_EDGES = 316;

    // --- Emisión de aristas: una por ciclo ---------------------------------------
    logic       running;
    logic [8:0] edge_ptr;     // Arista actual (0 a 315)
    logic [5:0] row_idx;      // Fila de la arista actual
    logic [5:0] edge_in_row;  // Posición de la arista dentro de su fila

    edge_info_t current_edge;
    row_info_t  current_row;
    logic       first_in_row, last_in_row;

    assign current_edge = EDGE_ROM[edge_ptr];
    assign current_row  = ROW_INFO_ROM[row_idx];
    assign u_addr       = current_edge.col_idx;
    assign first_in_row = (edge_in_row == 0);
    assign last_in_row  = (edge_in_row == current_row.num_edges - 1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running     <= 1'b0;
            edge_ptr    <= '0;
            row_idx     <= '0;
            edge_in_row <= '0;
        end else if (start && !running) begin
            running     <= 1'b1;
            edge_ptr    <= '0;
            row_idx     <= '0;
            edge_in_row <= '0;
        end else if (running) begin
            if (edge_ptr == TOTAL_EDGES - 1) running <= 1'b0;
            edge_ptr <= edge_ptr + 1'b1;
            if (last_in_row) begin
                row_idx     <= row_idx + 1'b1;
                edge_in_row <= '0;
            end else begin
                edge_in_row <= edge_in_row + 1'b1;
            end
        end
    end

    // --- Etapa de acumulación (llega el dato de la arista emitida el ciclo anterior)
    logic       acc_valid, acc_first, acc_last;
    logic [8:0] acc_shift;
    logic [5:0] acc_row;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) acc_valid <= 1'b0;
        else        acc_valid <= running;
    end

    always_ff @(posedge clk) begin
        acc_first <= first_in_row;
        acc_last  <= last_in_row;
        acc_shift <= current_edge.shift_val;
        acc_row   <= row_idx;
    end

    logic [383:0] rotated, acc;

    barrel_shifter_384 shifter_inst (
        .data_in  (u_data_in),
        .shift_val(acc_shift),
        .data_out (rotated)
    );

    always_ff @(posedge clk) begin
        if (acc_valid) acc <= (acc_first ? '0 : acc) ^ rotated;
    end

    // La fila completa queda en 'acc' el ciclo siguiente a su última arista: ese
    // ciclo se emite (aunque 'acc' ya esté acumulando la primera arista de la
    // siguiente fila, el consumidor captura el valor anterior en el flanco).
    // 'done' llega el ciclo siguiente a la última fila.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            syndrome_valid   <= 1'b0;
            syndrome_row_idx <= '0;
            done             <= 1'b0;
        end else begin
            syndrome_valid   <= acc_valid && acc_last;
            syndrome_row_idx <= acc_row;
            done             <= syndrome_valid && (syndrome_row_idx == 6'd45);
        end
    end

    assign syndrome_data = acc;

endmodule
