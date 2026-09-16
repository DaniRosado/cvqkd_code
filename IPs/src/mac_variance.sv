`timescale 1ns / 1ps

module mac_variance (
    input  logic               clk,
    input  logic               rst,      // Reset general del sistema
    input  logic               clear,    // Limpia los acumuladores para empezar una nueva trama
    input  logic               enable,   // Si vale 1, el dato es válido y entra a la tubería
    input  logic signed [15:0] data_in,  // El dato de Bob (Q_B o P_B)

    output logic signed [63:0] sum_sq,   // Salida: Sumatorio de X^2
    output logic signed [63:0] sum_val   // Salida: Sumatorio de X (Media)
);

    // =========================================================================
    // PIPELINE STAGE 1: Registros de Entrada (Mejora el Timing/Frecuencia)
    // =========================================================================
    logic signed [15:0] reg_data_in;
    logic               reg_enable_stg1;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            reg_data_in     <= '0;
            reg_enable_stg1 <= 1'b0;
        end else begin
            reg_data_in     <= data_in;
            reg_enable_stg1 <= enable;
        end
    end

    // =========================================================================
    // PIPELINE STAGE 2: Multiplicador (Infiere el bloque DSP48)
    // =========================================================================
    logic signed [31:0] square_mult;
    logic signed [15:0] val_bypass; // Pasamos el dato normal a la siguiente etapa
    logic               reg_enable_stg2;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            square_mult     <= '0;
            val_bypass      <= '0;
            reg_enable_stg2 <= 1'b0;
        end else if (reg_enable_stg1) begin
            // Multiplicación en punto fijo con signo
            square_mult     <= reg_data_in * reg_data_in; 
            val_bypass      <= reg_data_in;
            reg_enable_stg2 <= 1'b1;
        end else begin
            reg_enable_stg2 <= 1'b0;
        end
    end

    // =========================================================================
    // PIPELINE STAGE 3: Acumuladores de 64 bits
    // =========================================================================
    // OJO: Usamos registros internos para acumular y los conectamos a la salida.
    logic signed [63:0] accum_sq;
    logic signed [63:0] accum_val;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            accum_sq  <= '0;
            accum_val <= '0;
        end else if (reg_enable_stg2) begin
            // Extendemos el signo automáticamente al sumar a 64 bits
            accum_sq  <= accum_sq  + square_mult;
            accum_val <= accum_val + val_bypass;
        end
    end

    // Asignación continua a los puertos de salida
    assign sum_sq  = accum_sq;
    assign sum_val = accum_val;

endmodule