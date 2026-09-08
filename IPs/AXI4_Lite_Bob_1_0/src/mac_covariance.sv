`timescale 1ns / 1ps

module mac_covariance (
    input  logic               clk,
    input  logic               rst,
    input  logic               clear,
    input  logic               enable,
    
    // Entradas duales (Bob desde la BRAM Ping-Pong, Alice desde su BRAM)
    input  logic signed [15:0] data_bob,
    input  logic signed [15:0] data_alice,

    // Acumuladores de salida (64 bits para evitar desbordamientos)
    output logic signed [63:0] sum_cov,        // Sumatorio cruzado: A * B
    output logic signed [63:0] sum_val_bob,    // Sumatorio simple de Bob
    output logic signed [63:0] sum_val_alice   // Sumatorio simple de Alice
);

    // =========================================================================
    // PIPELINE STAGE 1: Captura de Entradas (Sincronización a 100 MHz)
    // =========================================================================
    logic signed [15:0] reg_bob;
    logic signed [15:0] reg_alice;
    logic               reg_enable_stg1;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            reg_bob         <= '0;
            reg_alice       <= '0;
            reg_enable_stg1 <= 1'b0;
        end else begin
            reg_bob         <= data_bob;
            reg_alice       <= data_alice;
            reg_enable_stg1 <= enable;
        end
    end

    // =========================================================================
    // PIPELINE STAGE 2: Multiplicador DSP48
    // =========================================================================
    logic signed [31:0] cross_mult;
    logic signed [15:0] bypass_bob;
    logic signed [15:0] bypass_alice;
    logic               reg_enable_stg2;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            cross_mult      <= '0;
            bypass_bob      <= '0;
            bypass_alice    <= '0;
            reg_enable_stg2 <= 1'b0;
        end else if (reg_enable_stg1) begin
            // Multiplicamos Alice * Bob en hardware dedicado
            cross_mult      <= reg_bob * reg_alice; 
            bypass_bob      <= reg_bob;
            bypass_alice    <= reg_alice;
            reg_enable_stg2 <= 1'b1;
        end else begin
            reg_enable_stg2 <= 1'b0;
        end
    end

    // =========================================================================
    // PIPELINE STAGE 3: Acumuladores Gigantes
    // =========================================================================
    logic signed [63:0] accum_cov;
    logic signed [63:0] accum_bob;
    logic signed [63:0] accum_alice;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            accum_cov   <= '0;
            accum_bob   <= '0;
            accum_alice <= '0;
        end else if (reg_enable_stg2) begin
            accum_cov   <= accum_cov   + cross_mult;
            accum_bob   <= accum_bob   + bypass_bob;
            accum_alice <= accum_alice + bypass_alice;
        end
    end

    // =========================================================================
    // SALIDAS
    // =========================================================================
    assign sum_cov       = accum_cov;
    assign sum_val_bob   = accum_bob;
    assign sum_val_alice = accum_alice;

endmodule