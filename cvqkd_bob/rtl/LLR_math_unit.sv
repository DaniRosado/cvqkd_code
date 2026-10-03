`timescale 1ns / 1ps

module LLR_math_unit #(
    parameter signed [63:0] N_SAMPLES = 64'sd13056,
    // round(2^48 / (2 * N^2)) = 825635 para N = 13056 (se deriva de N_SAMPLES)
    parameter signed [63:0] INV_2N2   = ((64'sd1 <<< 48) + N_SAMPLES * N_SAMPLES) / (2 * N_SAMPLES * N_SAMPLES)
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        start_calc, // Pulso de inicio cuando la FSM termina
    
    // Datos desde los MACs
    input  logic signed [63:0] sum_sq_P_B, sum_P_B, sum_cov_P, sum_P_A,
    input  logic signed [63:0] sum_sq_Q_B, sum_Q_B, sum_cov_Q, sum_Q_A,
    
    // Calibración
    input  logic signed [31:0] calib_VarA,
    
    // Salidas para el cálculo de LLR
    output logic signed [31:0] T_final,     // (Cov/V_A)^2 = T*eta/2 en heterodino (Q16.16)
    output logic signed [31:0] T_sqrt,      // Cov/V_A = sqrt(T*eta/2) (Q16.16)
    output logic signed [31:0] sigma_sq,    // Varianza sigma^2 (Q16.16)
    output logic signed [31:0] sigma,       // Desviación estándar sigma (Q16.16)
    output logic               data_ready
);

    // --- Señales de control del pipeline ---
    logic pipe_v1, pipe_v2, pipe_v3;

    // ===========================================================
    // ETAPA 1: Productos cruzados ((Sum)^2 y SumA*SumB)
    // ===========================================================
    // Estos cálculos son IMPRESCINDIBLES para la fórmula:
    // Var = (N*SumSq - (Sum)^2) / N^2
    //
    // Con N < 16384 muestras de 16 bits, |Sum| < N * 2^15 < 2^29: las sumas
    // simples caben en 30 bits con signo y los productos son de 30x30 bits (4 DSP48
    // cada uno) en lugar de 64x64, con el mismo resultado exacto.
    localparam int SUM_W = 30;
    logic signed [SUM_W-1:0] s_P_A, s_P_B, s_Q_A, s_Q_B;
    assign s_P_A = sum_P_A[SUM_W-1:0];
    assign s_P_B = sum_P_B[SUM_W-1:0];
    assign s_Q_A = sum_Q_A[SUM_W-1:0];
    assign s_Q_B = sum_Q_B[SUM_W-1:0];

    logic signed [63:0] cross_P_AB, cross_Q_AB;
    logic signed [63:0] sq_sum_P_B, sq_sum_Q_B;

    always_ff @(posedge clk) begin
        if (rst) pipe_v1 <= 1'b0;
        else     pipe_v1 <= start_calc;
        if (start_calc) begin
            cross_P_AB <= s_P_A * s_P_B;
            cross_Q_AB <= s_Q_A * s_Q_B;
            sq_sum_P_B <= s_P_B * s_P_B; // Necesario para la varianza
            sq_sum_Q_B <= s_Q_B * s_Q_B; // Necesario para la varianza
        end
    end

    // ===========================================================
    // ETAPA 2: Numeradores (Precisión de 64 bits)
    // ===========================================================
    // Las sumas de productos cumplen |Sum(x*y)| <= N * 2^30 < 2^44: la suma P + Q
    // cabe en 46 bits con signo, y N * (P + Q) en 60.
    localparam int PROD_W = 45;
    logic signed [PROD_W:0] cov_PQ, sq_PQ;
    assign cov_PQ = $signed(sum_cov_P[PROD_W-1:0])  + $signed(sum_cov_Q[PROD_W-1:0]);
    assign sq_PQ  = $signed(sum_sq_P_B[PROD_W-1:0]) + $signed(sum_sq_Q_B[PROD_W-1:0]);

    logic signed [63:0] num_cov_AB, num_var_B;

    always_ff @(posedge clk) begin
        if (rst) pipe_v2 <= 1'b0;
        else     pipe_v2 <= pipe_v1;
        if (pipe_v1) begin
            num_cov_AB <= (N_SAMPLES * cov_PQ) - (cross_P_AB + cross_Q_AB);
            num_var_B  <= (N_SAMPLES * sq_PQ)  - (sq_sum_P_B + sq_sum_Q_B);
        end
    end

    // ===========================================================
    // ETAPA 3: Normalización y Escala Q16.16
    // Multiplicamos por el inverso de 2N^2 (21 bits): el producto de 64 x 21 bits
    // no desborda y basta con 85 bits.
    // ===========================================================
    localparam logic signed [20:0] INV_2N2_W = 21'(INV_2N2);
    logic signed [84:0] cov_scaled, var_scaled;
    assign cov_scaled = num_cov_AB * INV_2N2_W;
    assign var_scaled = num_var_B  * INV_2N2_W;

    logic signed [31:0] cov_AB_pure;
    logic signed [31:0] var_B_pure;

    always_ff @(posedge clk) begin
        if (rst) begin
            {cov_AB_pure, var_B_pure} <= '0;
            pipe_v3 <= 1'b0;
        end else begin
            pipe_v3 <= pipe_v2;
            // Solo se actualizan con un cálculo nuevo: sigma_sq queda estable para la CPU
            if (pipe_v2) begin
                cov_AB_pure <= 32'(cov_scaled >>> 48);   // Dividir entre (2*N^2)
                var_B_pure  <= 32'(var_scaled >>> 48);
            end
        end
    end

    // Asignación de sigma_sq
    assign sigma_sq = var_B_pure;

    // ===========================================================
    // ETAPA 4: IPs de División y Raíz Cuadrada
    // ===========================================================
    
    // 1. División para obtener T
    logic [47:0] div_t_raw;
    logic        div_done;

    div_gen_48_32_params div_inst (
        .aclk(clk),
        .s_axis_divisor_tdata(calib_VarA),    
        .s_axis_divisor_tvalid(pipe_v3),
        .s_axis_dividend_tdata(cov_AB_pure),  
        .s_axis_dividend_tvalid(pipe_v3),
        .m_axis_dout_tdata(div_t_raw),
        .m_axis_dout_tvalid(div_done)
    );
    // 2. Raíz Cuadrada para Sigma = sqrt(sigma_sq)
    logic [31:0] sqrt_sigma_raw;
    cordic_sqrt_q16_16 sqrt_sigma_inst (
        .aclk(clk),
        .s_axis_cartesian_tdata(sigma_sq),
        .s_axis_cartesian_tvalid(pipe_v3),
        .m_axis_dout_tdata(sqrt_sigma_raw),
        .m_axis_dout_tvalid() // Podríamos usar este valid también si queremos esperar
    );
    assign sigma = sqrt_sigma_raw << 16;

    // 3. Obtener T (Transmitancia) elevando Sqrt(T) al cuadrado
    // La salida del divisor es Cov/V_A = sqrt(T*eta/2)
    assign T_sqrt = div_t_raw[31:0] << 1;
    
    // Multiplicamos para obtener T*eta/2 (Formato Q16.16)
    logic signed [63:0] t_sq_full;
    assign t_sq_full = $signed(T_sqrt) * $signed(T_sqrt);
    
    // T_final es el cuadrado, desplazado 16 bits para mantener el formato Q16.16
    assign T_final = t_sq_full[47:16];
    
    // Como eliminamos el IP CORDIC extra de T, pasamos la validación directamente
    assign data_ready = div_done;

endmodule