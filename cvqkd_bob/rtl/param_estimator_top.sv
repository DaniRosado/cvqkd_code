`timescale 1ns / 1ps

module param_estimator_top #(
    parameter int NUM_SAMPLES = 26112/2
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // --- Control Global ---
    input  logic        start,
    output logic        done,
    
    // --- Interfaz de Streaming (FIFOs de Entrada) ---
    input  logic        bob_stream_valid,
    input  logic [31:0] bob_stream_data,   // {Q_Bob, P_Bob}
    
    input  logic        alice_stream_valid,
    input  logic [31:0] alice_stream_data, // {Q_Alice, P_Alice}
    
    // ==========================================================
    // --- INTERFAZ HACIA EL WRAPPER AXI4-LITE (Solo CPU) ---
    // ==========================================================
    // Entradas (Escritas por la CPU mediante AXI)
    input  logic signed [31:0] calib_VarA,
    input  logic               skr_valid, // 1 = La CPU ha escrito el SKR
    input  logic signed [31:0] skr_in,    // El valor exacto del SKR calculado en C
    
    // Salidas (Leídas por la CPU mediante AXI)
    output logic signed [31:0] T_final_out,
    output logic signed [31:0] sigma_sq_out,
    output logic signed [31:0] sigma_out,
    output logic [31:0]        num_samples_out,
    
    // Señal de Interrupción
    output logic               irq,
    
    // ==========================================================
    // --- SALIDAS HACIA EL RESTO DEL HARDWARE (Globales) ---
    // ==========================================================
    output logic               frame_valid_out, // 1 = Trama segura, 0 = Trama comprometida
    output logic signed [31:0] T_sqrt_out,      // Para el destilador de Alice
    output logic signed [31:0] skr_out          // SKR propagado al resto del chip
);

    // =================================================================
    // 1. FIFOS GEMELAS (Entrada de Datos)
    // =================================================================
    logic        read_fifos;
    logic [31:0] bob_fifo_dout, alice_fifo_dout;
    logic        bob_empty, alice_empty;
    logic        bob_full, alice_full;

    sync_fifo #(.DATA_WIDTH(32), .DEPTH(1024)) fifo_bob_inst (
        .clk(clk), .rst(~rst_n), 
        .we (bob_stream_valid), .din(bob_stream_data),
        .re (read_fifos), .dout(bob_fifo_dout),
        .empty(bob_empty), .full(bob_full)
    );

    sync_fifo #(.DATA_WIDTH(32), .DEPTH(1024)) fifo_alice_inst (
        .clk(clk), .rst(~rst_n),
        .we (alice_stream_valid), .din(alice_stream_data),
        .re (read_fifos), .dout(alice_fifo_dout),
        .empty(alice_empty), .full(alice_full)
    );

    // =================================================================
    // 2. MICRO-CONTROLADOR DE FLUJO
    // =================================================================
    logic [14:0] muestras_procesadas;
    logic        mac_enable, mac_clear, start_math, working, math_done;

    assign read_fifos = (!bob_empty && !alice_empty) && (muestras_procesadas < NUM_SAMPLES) && !start_math;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_enable          <= 1'b0;
            mac_clear           <= 1'b1;
            muestras_procesadas <= '0;
            start_math          <= 1'b0;
            working             <= 1'b0;
        end else begin
            mac_clear <= 1'b0;
            if (start & !working) begin
                mac_clear           <= 1'b1;
                muestras_procesadas <= '0;
                start_math          <= 1'b0;
                working             <= 1'b1;
            end else begin
                mac_enable <= read_fifos;
                if (mac_enable) muestras_procesadas <= muestras_procesadas + 1'b1;
                
                if (mac_enable && (muestras_procesadas == NUM_SAMPLES - 1)) start_math <= 1'b1;
                else start_math <= 1'b0;
                
                if (done) working <= 1'b0; 
            end
        end
    end

    logic signed [15:0] bob_p, bob_q, alice_p, alice_q;
    assign bob_p   = bob_fifo_dout[15:0];
    assign bob_q   = bob_fifo_dout[31:16];
    assign alice_p = alice_fifo_dout[15:0];
    assign alice_q = alice_fifo_dout[31:16];

    // =================================================================
    // 3. ACELERADORES HARDWARE MAC Y UNIDAD MATEMÁTICA
    // =================================================================
    logic signed [63:0] var_P_sum_sq, var_P_sum_val, cov_P_sum_cov, cov_P_sum_alice, ignore_cov_bob_p;
    logic signed [63:0] var_Q_sum_sq, var_Q_sum_val, cov_Q_sum_cov, cov_Q_sum_alice, ignore_cov_bob_q;
    
    // Cables internos 
    logic signed [31:0] T_final_int, T_sqrt_int, sigma_sq_int, sigma_int;

    mac_variance var_P_inst (.clk(clk), .rst(~rst_n), .clear(mac_clear), .enable(mac_enable), .data_in(bob_p), .sum_sq(var_P_sum_sq), .sum_val(var_P_sum_val));
    mac_covariance cov_P_inst (.clk(clk), .rst(~rst_n), .clear(mac_clear), .enable(mac_enable), .data_bob(bob_p), .data_alice(alice_p), .sum_cov(cov_P_sum_cov), .sum_val_bob(ignore_cov_bob_p), .sum_val_alice(cov_P_sum_alice));
    mac_variance var_Q_inst (.clk(clk), .rst(~rst_n), .clear(mac_clear), .enable(mac_enable), .data_in(bob_q), .sum_sq(var_Q_sum_sq), .sum_val(var_Q_sum_val));
    mac_covariance cov_Q_inst (.clk(clk), .rst(~rst_n), .clear(mac_clear), .enable(mac_enable), .data_bob(bob_q), .data_alice(alice_q), .sum_cov(cov_Q_sum_cov), .sum_val_bob(ignore_cov_bob_q), .sum_val_alice(cov_Q_sum_alice));

    LLR_math_unit math_unit_inst (
        .clk(clk), .rst(~rst_n), .start_calc(start_math),
        .sum_sq_P_B(var_P_sum_sq), .sum_P_B(var_P_sum_val), .sum_cov_P(cov_P_sum_cov), .sum_P_A(cov_P_sum_alice),
        .sum_sq_Q_B(var_Q_sum_sq), .sum_Q_B(var_Q_sum_val), .sum_cov_Q(cov_Q_sum_cov), .sum_Q_A(cov_Q_sum_alice),
        .calib_VarA(calib_VarA),
        .T_final(T_final_int), .T_sqrt(T_sqrt_int), .sigma_sq(sigma_sq_int), .sigma(sigma_int),
        .data_ready(math_done)
    );

    // =================================================================
    // 4. MAPEO DE SALIDAS (Lectura asíncrona)
    // =================================================================
    assign num_samples_out = NUM_SAMPLES;
    assign T_final_out     = T_final_int;
    assign T_sqrt_out      = T_sqrt_int;     
    assign sigma_sq_out    = sigma_sq_int;
    assign sigma_out       = sigma_int;

    // =================================================================
    // 5. FSM DE COMUNICACIÓN CON LA CPU (Decisión Hardware de Seguridad)
    // =================================================================
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_WAIT_SKR,
        ST_DONE
    } cpu_fsm_t;

    cpu_fsm_t cpu_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_state       <= ST_IDLE;
            irq             <= 1'b0;
            frame_valid_out <= 1'b0;
            skr_out         <= '0;
            done            <= 1'b0;
        end else begin
            done <= 1'b0; 
            
            case (cpu_state)
                ST_IDLE: begin
                    frame_valid_out <= 1'b0;
                    irq             <= 1'b0;
                    
                    if (math_done) begin
                        irq       <= 1'b1; // Chispazo a la CPU
                        cpu_state <= ST_WAIT_SKR;
                    end
                end
                
                ST_WAIT_SKR: begin
                    irq <= 1'b0; 
                    
                    if (skr_valid) begin
                        // 1. Guardamos el SKR para el resto del HW
                        skr_out <= skr_in;
                        
                        // 2. EL HARDWARE JUZGA: ¿Es mayor que 0?
                        if (skr_in > 0) begin
                            frame_valid_out <= 1'b1; // Trama OK
                        end else begin
                            frame_valid_out <= 1'b0; // Eve detectada
                        end
                        
                        cpu_state <= ST_DONE;
                    end
                end
                
                ST_DONE: begin
                    done <= 1'b1;
                    if (!skr_valid) begin
                        cpu_state <= ST_IDLE;
                    end
                end
            endcase
        end
    end

endmodule