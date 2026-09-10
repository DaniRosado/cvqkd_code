`timescale 1ns / 1ps

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

    // Registros de la máquina de estados
    logic signed [THETA_WIDTH-1:0] theta_A;
    logic signed [THETA_WIDTH-1:0] delta_theta;
    logic signed [THETA_WIDTH-1:0] acumulador;
    logic [3:0] contador_datos;
    
    // Señal interna para el ángulo raw (sin negar ni retrasar)
    logic signed [THETA_WIDTH-1:0] theta_raw;

    // NUEVO: Calculamos la diferencia en 19 bits para evitar overflow
    logic signed [18:0] diff_raw;
    // IMPORTANTE: Extendemos el signo manualmente a 19 bits antes de restar.
    // Si no, Vivado usa un restador de 18 bits y +pi - (-pi) se desborda.
    assign diff_raw = $signed({theta_in[THETA_WIDTH-1], theta_in}) - $signed({theta_A[THETA_WIDTH-1], theta_A});

    typedef enum logic [1:0] {ESPERAR_A, ESPERAR_B, INTERPOLAR} state_t;
    // Constantes Matemáticas en formato Q4.15 (19 bits) para evitar desbordamiento
    localparam signed [18:0] CONST_PI     = 19'sd102944; // Pi
    localparam signed [18:0] CONST_TWO_PI = 19'sd205887; // 2 * Pi
    state_t estado_actual;

    // =========================================================================
    // 1. Lógica Principal (Cálculo de Fase)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            theta_A       <= '0;
            delta_theta   <= '0;
            acumulador    <= '0;
            contador_datos<= '0;
            fifo_re       <= 1'b0;
            theta_raw     <= '0;
            estado_actual <= ESPERAR_A;
        end else begin
            
            fifo_re <= 1'b0; // Por defecto, no pedimos datos a la FIFO

            case (estado_actual)
                ESPERAR_A: begin
                    if (valid_in) begin
                        theta_A <= theta_in;
                        estado_actual <= ESPERAR_B;
                    end
                end
                
                ESPERAR_B: begin
                    if (valid_in) begin
                        if (diff_raw > CONST_PI) begin
                            delta_theta <= (diff_raw - CONST_TWO_PI) >>> 4;
                        end else if (diff_raw < -CONST_PI) begin
                            delta_theta <= (diff_raw + CONST_TWO_PI) >>> 4;
                        end else begin
                            delta_theta <= diff_raw >>> 4;
                        end
                        acumulador <= theta_A;
                        contador_datos <= 4'd15;
                        theta_A <= theta_in; 
                        estado_actual <= INTERPOLAR;
                    end
                end
                
                INTERPOLAR: begin
                    if (contador_datos > 0) begin
                        
                        // Hacemos el chequeo de límites sumando al vuelo (promociona a 19 bits solo para el if)
                        if ( (acumulador + delta_theta) > CONST_PI ) begin
                            acumulador <= (acumulador + delta_theta) - CONST_TWO_PI;
                            theta_raw  <= (acumulador + delta_theta) - CONST_TWO_PI;
                        end 
                        else if ( (acumulador + delta_theta) < -CONST_PI ) begin
                            acumulador <= (acumulador + delta_theta) + CONST_TWO_PI;
                            theta_raw  <= (acumulador + delta_theta) + CONST_TWO_PI;
                        end 
                        else begin
                            acumulador <= acumulador + delta_theta;
                            theta_raw  <= acumulador + delta_theta; 
                        end
                        
                        fifo_re <= 1'b1; // ¡Pedimos el dato a la FIFO!
                        contador_datos <= contador_datos - 1'b1;
                        
                    end else begin
                        // Parche Seamless: Pescar el piloto al vuelo
                        if (valid_in) begin
                            if (diff_raw > CONST_PI) begin
                                delta_theta <= (diff_raw - CONST_TWO_PI) >>> 4;
                            end else if (diff_raw < -CONST_PI) begin
                                delta_theta <= (diff_raw + CONST_TWO_PI) >>> 4;
                            end else begin
                                delta_theta <= diff_raw >>> 4;
                            end
                            acumulador <= theta_A;
                            contador_datos <= 4'd15;
                            theta_A <= theta_in; 
                            estado_actual <= INTERPOLAR; 
                        end else begin
                            estado_actual <= ESPERAR_B; 
                        end
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // 2. Registro de Pipeline (Sincronización con FIFO y cambio de signo)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            cordic_valid <= 1'b0;
            cordic_theta <= '0;
        end else begin
            cordic_valid <= fifo_re;
            // ¡EL TRUCO! Negamos el ángulo para deshacer la rotación
            cordic_theta <= -theta_raw; 
        end
    end

endmodule