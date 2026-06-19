`timescale 1ns / 1ps

module param_estimator_top #(
    parameter NUM_SAMPLES = 26112/2
)(
    input  logic        clk,
    input  logic        rst,
    
    // --- Control Global ---
    input  logic        start,
    output logic        done,
    
    // --- NUEVA INTERFAZ DE STREAMING (En sustitución de las RAMs) ---
    input  logic        bob_stream_valid,
    input  logic [31:0] bob_stream_data,   // Viene del Router: {Q_Bob, P_Bob}
    
    input  logic        alice_stream_valid,
    input  logic [31:0] alice_stream_data, // Viene de la red clásica: {Q_Alice, P_Alice}
    
    // --- Entradas de Calibración ---
    input  logic signed [31:0] calib_VarA,
    
    // --- Salidas de Métricas de Seguridad (Q16.16) ---
    output logic signed [31:0] T_final,
    output logic signed [31:0] T_sqrt,
    output logic signed [31:0] sigma_sq,
    output logic signed [31:0] sigma,
    output logic        data_ready
);

    // =================================================================
    // 1. INSTANCIACIÓN DE LAS FIFOS GEMELAS (Tu propio sync_fifo.sv)
    // =================================================================
    logic        read_fifos;
    logic [31:0] bob_fifo_dout, alice_fifo_dout;
    logic        bob_empty, alice_empty;
    logic        bob_full, alice_full;

    // FIFO de Bob: Almacena los datos de sacrificio enrutados
    sync_fifo #(
        .DATA_WIDTH(32),
        .DEPTH(1024) 
    ) fifo_bob_inst (
        .clk(clk),
        .rst(rst),
        .we (bob_stream_valid),
        .din(bob_stream_data),
        .re (read_fifos),
        .dout(bob_fifo_dout),
        .empty(bob_empty),
        .full(bob_full)
    );

    // FIFO de Alice: Almacena los datos recibidos de Alice por canal clásico
    sync_fifo #(
        .DATA_WIDTH(32),
        .DEPTH(1024)
    ) fifo_alice_inst (
        .clk(clk),
        .rst(rst),
        .we (alice_stream_valid),
        .din(alice_stream_data),
        .re (read_fifos),
        .dout(alice_fifo_dout),
        .empty(alice_empty),
        .full(alice_full)
    );

    // =================================================================
    // 2. MICRO-CONTROLADOR DE FLUJO (Streaming Controller)
    // =================================================================
    logic [14:0] muestras_procesadas;
    logic        mac_enable;
    logic        mac_clear;
    logic        start_math;

    // Leemos de las FIFOs solo si ambas tienen datos y no hemos terminado el bloque
    assign read_fifos = (!bob_empty && !alice_empty) && (muestras_procesadas < NUM_SAMPLES) && !start_math;

    always_ff @(posedge clk) begin
        if (rst) begin
            mac_enable          <= 1'b0;
            mac_clear           <= 1'b1;
            muestras_procesadas <= '0;
            start_math          <= 1'b0;
            done                <= 1'b0;
        end else begin
            mac_clear <= 1'b0;
            
            if (start) begin
                mac_clear           <= 1'b1; // Pulso para resetear acumuladores MAC
                muestras_procesadas <= '0;
                start_math          <= 1'b0;
                done                <= 1'b0;
            end else begin
                // Como tu FIFO tarda 1 ciclo en sacar el dato, retrasamos read_fifos
                mac_enable <= read_fifos;
                
                if (mac_enable) begin
                    muestras_procesadas <= muestras_procesadas + 1'b1;
                end
                
                // Cuando procesamos la última muestra, disparamos la unidad matemática
                if (muestras_procesadas == NUM_SAMPLES && !done) begin
                    start_math <= 1'b1;
                end else begin
                    start_math <= 1'b0;
                end
                
                // El proceso global termina cuando la LLR_math_unit da el data_ready
                if (data_ready) begin
                    done <= 1'b1;
                end
            end
        end
    end

    // Desempaquetamos los datos de salida de las FIFOs ({Q, P}) para los MACs
    logic signed [15:0] bob_p, bob_q;
    logic signed [15:0] alice_p, alice_q;

    assign bob_p   = bob_fifo_dout[15:0];
    assign bob_q   = bob_fifo_dout[31:16];
    assign alice_p = alice_fifo_dout[15:0];
    assign alice_q = alice_fifo_dout[31:16];

    // =================================================================
    // 3. ACELERADORES HARDWARE (Multiplicadores MAC de 64 bits)
    // =================================================================
    logic signed [63:0] var_P_sum_sq, var_P_sum_val;
    logic signed [63:0] cov_P_sum_cov, cov_P_sum_alice, ignore_cov_bob_p;
    logic signed [63:0] var_Q_sum_sq, var_Q_sum_val;
    logic signed [63:0] cov_Q_sum_cov, cov_Q_sum_alice, ignore_cov_bob_q;

    // --- Cuadratura P ---
    mac_variance var_P_inst (
        .clk(clk), .rst(rst), .clear(mac_clear), .enable(mac_enable), .data_in(bob_p),
        .sum_sq(var_P_sum_sq), .sum_val(var_P_sum_val)
    );

    mac_covariance cov_P_inst (
        .clk(clk), .rst(rst), .clear(mac_clear), .enable(mac_enable),
        .data_bob(bob_p), .data_alice(alice_p),
        .sum_cov(cov_P_sum_cov), .sum_val_bob(ignore_cov_bob_p), .sum_val_alice(cov_P_sum_alice)
    );

    // --- Cuadratura Q ---
    mac_variance var_Q_inst (
        .clk(clk), .rst(rst), .clear(mac_clear), .enable(mac_enable), .data_in(bob_q),
        .sum_sq(var_Q_sum_sq), .sum_val(var_Q_sum_val)
    );

    mac_covariance cov_Q_inst (
        .clk(clk), .rst(rst), .clear(mac_clear), .enable(mac_enable),
        .data_bob(bob_q), .data_alice(alice_q),
        .sum_cov(cov_Q_sum_cov), .sum_val_bob(ignore_cov_bob_q), .sum_val_alice(cov_Q_sum_alice)
    );

    // =================================================================
    // 4. UNIDAD MATEMÁTICA FINAL (Divisiones e IPs CORDIC)
    // =================================================================
    LLR_math_unit math_unit_inst (
        .clk(clk), .rst(rst), .start_calc(start_math),
        .sum_sq_P_B(var_P_sum_sq), .sum_P_B(var_P_sum_val), .sum_cov_P(cov_P_sum_cov), .sum_P_A(cov_P_sum_alice),
        .sum_sq_Q_B(var_Q_sum_sq), .sum_Q_B(var_Q_sum_val), .sum_cov_Q(cov_Q_sum_cov), .sum_Q_A(cov_Q_sum_alice),
        .calib_VarA(calib_VarA),
        .T_final(T_final), .T_sqrt(T_sqrt), .sigma_sq(sigma_sq), .sigma(sigma),
        .data_ready(data_ready)
    );

endmodule