`timescale 1ns / 1ps

module ldpc_layer_datapath #(
    parameter int Z = 384,
    parameter int W = 8
)(
    input  logic              clk,
    input  logic              rst_n,
    
    // Control desde la FSM
    input  logic [8:0]        shift_val,    // Valor de la ROM para esta conexión
    input  logic              cnu_vnu_ctrl, // Control de fase (Actualizar CNU o VNU)
    
    // Interfaz con Memorias BRAM
    input  logic [Z*W-1:0]    p_mem_data,   // LLR Total (P) desde la RAM
    input  logic [Z*W-1:0]    r_mem_data,   // Mensaje viejo (R_old) desde la RAM
    
    // Salidas hacia las Memorias BRAM
    output logic [Z*W-1:0]    p_mem_new,    // Nuevo LLR Total a guardar
    output logic [Z*W-1:0]    r_mem_new     // Nuevo mensaje CNU a guardar
);

    // =========================================================================
    // 1. Red de Alineación de Entrada (Forward Shifter)
    // =========================================================================
    logic [Z*W-1:0] p_shifted;
    logic [Z*W-1:0] r_old_shifted;

    // Rotamos los datos que salen de la RAM para alinearlos con las CNUs
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

    // =========================================================================
    // 2. Procesamiento Paralelo (384 Nodos)
    // =========================================================================
    logic [Z*W-1:0] vnu_to_cnu_bus;
    logic [Z*W-1:0] cnu_to_vnu_bus;
    logic [Z*W-1:0] p_new_parallel;

    genvar i;
    generate
        for (i = 0; i < Z; i++) begin : gen_nodes
            // Instancia de VNU para cada uno de los 384 elementos
            vnu_processor #(.W(W)) vnu_inst (
                .clk(clk),
                .rst_n(rst_n),
                .p_n_in(p_shifted[i*W +: W]),
                .r_old_in(r_old_shifted[i*W +: W]),
                .r_new_in(cnu_to_vnu_bus[i*W +: W]), // Mensaje fresco de la CNU
                .q_mn_out(vnu_to_cnu_bus[i*W +: W]),
                .p_n_out(p_new_parallel[i*W +: W]),
                .hard_decision() // Se podría usar para early termination
            );
            
            // Aquí conectarías tus 384 CNUs (simplificado para el datapath)
            // cnu_serial_minsum cnu_inst (...);
        end
    endgenerate

    // =========================================================================
    // 3. Red de Realineación de Salida (Reverse Shifter)
    // =========================================================================
    // El valor de rotación inversa para un factor Z es: (Z - shift_val) % Z
    logic [8:0] inv_shift_val;
    assign inv_shift_val = (shift_val == 0) ? 9'd0 : 9'(Z - shift_val);

    // Devolvemos los LLRs actualizados a su posición original en la RAM
    barrel_shifter_word #(.Z(Z), .W(W)) rev_shifter_p (
        .data_in(p_new_parallel),
        .shift_val(inv_shift_val),
        .data_out(p_mem_new)
    );

    // Nota: El r_mem_new también pasaría por un shifter similar si fuera necesario
    assign r_mem_new = '0; // Placeholder para la lógica de la CNU

endmodule