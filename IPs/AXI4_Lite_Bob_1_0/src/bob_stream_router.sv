`timescale 1ns / 1ps

module bob_stream_router (
    input  logic        clk,
    input  logic        rst,
    
    // --- Interfaz con el DSP (Escritura a Ciegas) ---
    input  logic        dsp_valid,
    input  logic [31:0] dsp_data,   // Datos recuperados {Q_B, P_B}
    
    // --- Interfaz con la Máscara de Sacrificio (Lectura Controlada) ---
    input  logic        mask_valid, // 1 = El procesador manda un bit de máscara
    input  logic        mask_bit,   // 1 = Sacrificar, 0 = Clave (MDR)
    
    // --- Salida 1: Hacia Estimación de Parámetros ---
    output logic        valid_sac,
    output logic [31:0] data_sac,
    
    // --- Salida 2: Hacia Reconciliación (MDR/LDPC) ---
    output logic        valid_key,
    output logic [31:0] data_key
);

    // =========================================================================
    // 1. LA MEGA-FIFO (Almacenamiento Temporal Seguro)
    // =========================================================================
    logic        mega_fifo_re;
    logic [31:0] mega_fifo_dout;
    logic        mega_fifo_empty;
    logic        mega_fifo_full;

    // Instanciamos tu propia FIFO.
    // 65536 (2^16) es potencia de 2 y mayor que tu bloque de 52224.
    // Ocupará exactamente 2 Megabits de Block RAM (Perfecto para una Zynq).
    sync_fifo #(
        .DATA_WIDTH(32),
        .DEPTH(65536) 
    ) mega_fifo_inst (
        .clk(clk),
        .rst(rst),
        .we(dsp_valid),       // Escribimos a toda pastilla según llega del DSP
        .din(dsp_data),
        .re(mask_valid),    // Leemos solo cuando haya máscara
        .dout(mega_fifo_dout),
        .empty(mega_fifo_empty),
        .full(mega_fifo_full)
    );

    logic mask_valid_delayed;
    logic mask_bit_delayed;

    // lógica púramente combinacional (vamos a reescribir lo de arriba)
    assign data_sac = mega_fifo_dout;
    assign data_key = mega_fifo_dout;
    // necesitamos aguantar el valor de mask_bit y de mask_valid 1 ciclo
  
    always_ff @(posedge clk) begin
        mask_valid_delayed <= mask_valid;
        mask_bit_delayed <= mask_bit;
    end

    assign valid_sac = mask_valid_delayed && mask_bit_delayed && !mega_fifo_empty;
    assign valid_key = mask_valid_delayed && !mask_bit_delayed && !mega_fifo_empty;

endmodule