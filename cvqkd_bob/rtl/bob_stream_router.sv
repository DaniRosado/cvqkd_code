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
    output logic [31:0] data_key,

    // --- Diagnóstico ---
    output logic        data_loss   // Sticky: muestra del DSP descartada (FIFO llena)
                                    // o bit de máscara sin muestra (FIFO vacía)
);

    // =========================================================================
    // 1. LA MEGA-FIFO (Almacenamiento Temporal Seguro)
    // =========================================================================
    logic        mega_fifo_dout_valid;
    logic [31:0] mega_fifo_dout;
    logic        mega_fifo_empty;
    logic        mega_fifo_full;

    // Guarda los datos de una trama completa (26.115 muestras sin pilotos) mientras
    // llega la máscara: 32.768 (2^15) es la potencia de 2 inmediatamente superior.
    sync_fifo #(
        .DATA_WIDTH(32),
        .DEPTH(32768)
    ) mega_fifo_inst (
        .clk(clk),
        .rst(rst),
        .we(dsp_valid),       // Escribimos a toda pastilla según llega del DSP
        .din(dsp_data),
        .re(mask_valid),      // Leemos solo cuando haya máscara
        .dout(mega_fifo_dout),
        .empty(mega_fifo_empty),
        .full(mega_fifo_full)
    );

    assign data_sac = mega_fifo_dout;
    assign data_key = mega_fifo_dout;

    // La FIFO entrega el dato un ciclo después de la lectura: retrasamos la
    // condición de lectura REAL (máscara presente y FIFO no vacía en ese ciclo).
    logic mask_bit_delayed;

    always_ff @(posedge clk) begin
        if (rst) begin
            mega_fifo_dout_valid <= 1'b0;
            mask_bit_delayed     <= 1'b0;
            data_loss            <= 1'b0;
        end else begin
            mega_fifo_dout_valid <= mask_valid && !mega_fifo_empty;
            mask_bit_delayed     <= mask_bit;
            if ((mask_valid && mega_fifo_empty) || (dsp_valid && mega_fifo_full))
                data_loss <= 1'b1;
        end
    end

    assign valid_sac = mega_fifo_dout_valid &&  mask_bit_delayed;
    assign valid_key = mega_fifo_dout_valid && !mask_bit_delayed;

endmodule
