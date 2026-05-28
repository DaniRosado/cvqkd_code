`timescale 1ns / 1ps

module param_estimator_top #(
    parameter NUM_SAMPLES = 26112/2
)(
    input  logic        clk,
    input  logic        rst,
    
    input  logic        start,
    input  logic        ping_pong_bit,
    output logic        done,
    
    output logic [14:0] ptr_addr,       // i
    input  logic [15:0] ptr_data,       // Dato i de Bob (B)
    
    output logic [16:0] bob_addr,       // Dirección de datos de Bob (B)
    input  logic [31:0] bob_data,       // Datos de Bob (B) 
    
    output logic [14:0] alice_addr,     // Dirección de datos de Alice (A)
    input  logic [31:0] alice_data,     // Datos de Alice (A)
    
    // =================================================================
    // CONTROL DE FLUJO ON-THE-FLY
    // =================================================================
    input  logic [15:0] alice_items_avail, // Datos disponibles en Alice
    input  logic [15:0] bob_items_avail,   // Datos disponibles en Bob Ptr RAM

    
    // =================================================================
    // ENTRADAS DE CALIBRACIÓN (Reducidas solo a lo necesario para LLR)
    // =================================================================
    input  logic signed [31:0] calib_VarA,  // Varianza de Alice
    
    // =================================================================
    // SALIDAS ESTIMADAS (Q16.16) DIRECTAS HACIA EL DECODIFICADOR LDPC
    // =================================================================
    output logic signed [31:0] T_estimated,        // Sqrt(T*eta)
    output logic signed [31:0] T_sqrt_estimated,   // Sqrt(Sqrt(T*eta))
    output logic signed [31:0] sigma_sq_estimated, // Varianza de Bob
    output logic signed [31:0] sigma_estimated     // Desviación estándar
);

    // Desempaquetado de datos
    logic signed [15:0] bob_q, bob_p, alice_q, alice_p;
    assign {bob_q, bob_p}     = bob_data;
    assign {alice_q, alice_p} = alice_data;

    // Cables de control interno de la FSM
    logic mac_clear, mac_enable, start_math, math_done;

    // =================================================================
    // CABLES INTERNOS DE 64 BITS (Salida de los MACs)
    // =================================================================
    logic signed [63:0] var_P_sum_sq, var_P_sum_val, cov_P_sum_cov, cov_P_sum_alice;
    logic signed [63:0] var_Q_sum_sq, var_Q_sum_val, cov_Q_sum_cov, cov_Q_sum_alice;
    logic signed [63:0] ignore_cov_bob_p, ignore_cov_bob_q;

    // 1. EL CEREBRO (Máquina de Estados)
    fsm_estimator #(.NUM_SAMPLES(NUM_SAMPLES)) fsm_inst (
        .clk(clk), .rst(rst),
        .start(start), .ping_pong_bit(ping_pong_bit),
        .start_math(start_math), .math_done(math_done), 
        .done(done),
        .ptr_addr(ptr_addr), .ptr_data(ptr_data),
        .bob_addr(bob_addr), .alice_addr(alice_addr),
        .alice_items_avail(alice_items_avail),
        .bob_items_avail(bob_items_avail),
        .mac_clear(mac_clear), .mac_enable(mac_enable)
    );

    // 2. ACELERADORES P (Cuadratura In-Phase)
    mac_variance var_P_inst (
        .clk(clk), .rst(rst), .clear(mac_clear), .enable(mac_enable), .data_in(bob_p),
        .sum_sq(var_P_sum_sq), .sum_val(var_P_sum_val)
    );
    mac_covariance cov_P_inst (
        .clk(clk), .rst(rst), .clear(mac_clear), .enable(mac_enable),
        .data_bob(bob_p), .data_alice(alice_p),
        .sum_cov(cov_P_sum_cov), .sum_val_bob(ignore_cov_bob_p), .sum_val_alice(cov_P_sum_alice)
    );

    // 3. ACELERADORES Q (Cuadratura Quadrature)
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
    // 4. BLOQUE MATEMÁTICO DE RECONCILIACIÓN (LLR Math Unit)
    // =================================================================
    LLR_math_unit math_unit_inst (
        .clk(clk), 
        .rst(rst),
        .start_calc(start_math), 
        
        // Sumatorios P
        .sum_sq_P_B(var_P_sum_sq), .sum_P_B(var_P_sum_val), 
        .sum_cov_P(cov_P_sum_cov), .sum_P_A(cov_P_sum_alice),
        
        // Sumatorios Q
        .sum_sq_Q_B(var_Q_sum_sq), .sum_Q_B(var_Q_sum_val), 
        .sum_cov_Q(cov_Q_sum_cov), .sum_Q_A(cov_Q_sum_alice),
        
        // Entrada de Calibración
        .calib_VarA(calib_VarA), 
        
        // Salidas hacia el bloque LDPC
        .T_final(T_estimated),
        .T_sqrt(T_sqrt_estimated),
        .sigma_sq(sigma_sq_estimated),
        .sigma(sigma_estimated),
        
        // Feedback para la FSM
        .data_ready(math_done)  
    );

endmodule