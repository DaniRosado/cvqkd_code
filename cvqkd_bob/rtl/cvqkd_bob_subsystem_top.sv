`timescale 1ns / 1ps

module cvqkd_bob_subsystem_top #(
    parameter ADC_WIDTH   = 16,
    parameter NUM_SAMPLES = 26112/2 // 13056 Muestras de sacrificio
)(
    input  logic        clk,
    input  logic        rst,
    
    // --- Interfaz de Entrada desde el ADC (Canal Cuántico) ---
    input  logic signed [ADC_WIDTH-1:0] p_in,
    input  logic signed [ADC_WIDTH-1:0] q_in,
    input  logic                        valid_in,
    
    // --- Interfaz de Control Clásico (Procesador ARM / Bloque de Control) ---
    input  logic                        start_est,
    input  logic signed [31:0]          calib_VarA,
    input  logic                        mask_valid,
    input  logic                        mask_bit,
    
    // --- Entrada del canal clásico para Alice ---
    input  logic                        alice_stream_valid,
    input  logic [31:0]                 alice_stream_data,   // {Q_Alice, P_Alice}
    
    // --- Interfaz de Clave Privada (Hacia Reconciliación MDR / LDPC) ---
    output logic                        valid_key,
    output logic [31:0]                 data_key,            // {Q_Bob, P_Bob} para la clave
    
    // --- Salidas de Métricas de Seguridad (Hacia el Procesador ARM) ---
    output logic                        done_est,
    output logic                        data_ready_est,
    output logic signed [31:0]          T_final,
    output logic signed [31:0]          T_sqrt,
    output logic signed [31:0]          sigma_sq,
    output logic signed [31:0]          sigma
);

    // =========================================================================
    // CABLES INTERNOS DE INTERCONEXIÓN
    // =========================================================================
    logic signed [ADC_WIDTH-1:0] dsp_p_out;
    logic signed [ADC_WIDTH-1:0] dsp_q_out;
    logic                        dsp_valid_out;
    
    logic [31:0] dsp_data_packed;
    
    logic        router_valid_sac;
    logic [31:0] router_data_sac;

    // Empaquetamos las cuadraturas recuperadas por el DSP en un bus único de 32 bits
    assign dsp_data_packed = {dsp_q_out, dsp_p_out};

    // =========================================================================
    // 1. BLOQUE DSP: RECUPERACIÓN DE FASE VECTORIZADA
    // =========================================================================
    cvqkd_bob_dsp_top #(
        .ADC_WIDTH(ADC_WIDTH)
        //.DSP_WIDTH(18) // Formato expandido para CORDIC
    ) dsp_inst (
        .clk(clk),
        .rst(rst),
        .p_in(p_in),
        .q_in(q_in),
        .valid_in(valid_in),
        .p_out(dsp_p_out),
        .q_out(dsp_q_out),
        .valid_out(dsp_valid_out)
    );

    // =========================================================================
    // 2. ENRUTADOR DE STREAMING: BUFFER SEGURO MEGA-FIFO
    // =========================================================================
    bob_stream_router router_inst (
        .clk(clk),
        .rst(rst),
        .dsp_valid(dsp_valid_out),
        .dsp_data(dsp_data_packed),
        .mask_valid(mask_valid),
        .mask_bit(mask_bit),
        .valid_sac(router_valid_sac),
        .data_sac(router_data_sac),
        .valid_key(valid_key),   // Directo al puerto del TOP para el MDR
        .data_key(data_key)      // Directo al puerto del TOP para el MDR
    );

    // =========================================================================
    // 3. ACELERADOR DE ESTIMACIÓN DE PARÁMETROS
    // =========================================================================
    param_estimator_top #(
        .NUM_SAMPLES(NUM_SAMPLES)
    ) param_estimator_inst (
        .clk(clk),
        .rst(rst),
        .start(mask_valid),
        .done(done_est),
        .bob_stream_valid(router_valid_sac),
        .bob_stream_data(router_data_sac),
        .alice_stream_valid(alice_stream_valid),
        .alice_stream_data(alice_stream_data),
        .calib_VarA(calib_VarA),
        .T_final(T_final),
        .T_sqrt(T_sqrt),
        .sigma_sq(sigma_sq),
        .sigma(sigma),
        .data_ready(data_ready_est)
    );

    // =========================================================================
    // HUECO RESERVADO: GENERACIÓN DE SÍNDROME Y MDR (RECONCILIACIÓN)
    // =========================================================================
    // Las señales 'valid_key' y 'data_key' alimentarán en el futuro el 
    // bloque mdr_bob_top y las memorias BRAM del decodificador LDPC.

endmodule