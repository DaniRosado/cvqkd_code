`timescale 1ns / 1ps

// =============================================================================
// Interpolador de fase entre pilotos (1 piloto cada 16 símbolos).
// Con dos pilotos consecutivos theta_A y theta_B calcula la pendiente
// delta = wrap(theta_B - theta_A) / 16 y genera la fase de los 15 datos
// intermedios (theta_A + k * delta, envuelta a [-pi, pi]). Por cada dato pide su
// muestra a la FIFO y entrega al CORDIC de rotación la fase negada un ciclo
// después, alineada con la salida de la FIFO.
// =============================================================================
module phase_interpolator #(
    parameter THETA_WIDTH = 18
)(
    input  logic clk,
    input  logic rst,
    input  logic signed [THETA_WIDTH-1:0] theta_in,
    input  logic                          valid_in,

    // Salida hacia la FIFO (inmediata)
    output logic                          fifo_re,

    // Salidas hacia el CORDIC 2 (retrasadas 1 ciclo y negadas)
    output logic signed [THETA_WIDTH-1:0] cordic_theta,
    output logic                          cordic_valid
);

    // Constantes en Q4.15 (19 bits, un bit más que las fases para no desbordar)
    localparam signed [18:0] CONST_PI     = 19'sd102944;
    localparam signed [18:0] CONST_TWO_PI = 19'sd205887;

    // Lleva un ángulo de (-2pi, 2pi) al intervalo [-pi, pi]
    function automatic logic signed [18:0] wrap_pi(input logic signed [18:0] x);
        if (x > CONST_PI)       return x - CONST_TWO_PI;
        else if (x < -CONST_PI) return x + CONST_TWO_PI;
        else                    return x;
    endfunction

    typedef enum logic [1:0] {ESPERAR_A, ESPERAR_B, INTERPOLAR} state_t;
    state_t estado_actual;

    logic signed [THETA_WIDTH-1:0] theta_A;        // Último piloto recibido
    logic signed [THETA_WIDTH-1:0] delta_theta;    // Pendiente entre pilotos (por símbolo)
    logic signed [THETA_WIDTH-1:0] acumulador;     // Fase del dato actual
    logic signed [THETA_WIDTH-1:0] theta_raw;      // Fase entregada (sin negar ni retrasar)
    logic [3:0]                    contador_datos; // Datos que faltan por interpolar

    // Diferencia entre pilotos y siguiente fase, en 19 bits (+pi - (-pi) no desborda)
    logic signed [18:0] diff_raw, step_sum;
    assign diff_raw = theta_in   - theta_A;
    assign step_sum = acumulador + delta_theta;

    always_ff @(posedge clk) begin
        if (rst) begin
            theta_A        <= '0;
            delta_theta    <= '0;
            acumulador     <= '0;
            contador_datos <= '0;
            fifo_re        <= 1'b0;
            theta_raw      <= '0;
            estado_actual  <= ESPERAR_A;
        end else begin
            fifo_re <= 1'b0;
            if (estado_actual == ESPERAR_A) begin
                if (valid_in) begin
                    theta_A       <= theta_in;
                    estado_actual <= ESPERAR_B;
                end
            end else if (estado_actual == INTERPOLAR && contador_datos != 0) begin
                // Siguiente dato: avanzamos la fase y pedimos su muestra a la FIFO
                acumulador     <= wrap_pi(step_sum);
                theta_raw      <= wrap_pi(step_sum);
                fifo_re        <= 1'b1;
                contador_datos <= contador_datos - 1'b1;
            end else if (valid_in) begin
                // Nuevo piloto (también justo al acabar la interpolación anterior)
                delta_theta    <= wrap_pi(diff_raw) >>> 4;
                acumulador     <= theta_A;
                contador_datos <= 4'd15;
                theta_A        <= theta_in;
                estado_actual  <= INTERPOLAR;
            end else begin
                estado_actual  <= ESPERAR_B;
            end
        end
    end

    // Registro de salida: sincronización con la FIFO y cambio de signo para
    // deshacer la rotación del canal
    always_ff @(posedge clk) begin
        if (rst) begin
            cordic_valid <= 1'b0;
            cordic_theta <= '0;
        end else begin
            cordic_valid <= fifo_re;
            cordic_theta <= -theta_raw;
        end
    end

endmodule
