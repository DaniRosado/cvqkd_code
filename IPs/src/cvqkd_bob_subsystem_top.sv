`timescale 1ns / 1ps

module cvqkd_bob_subsystem_top #(
    parameter ADC_WIDTH   = 16,
    parameter NUM_SAMPLES = 26112/2 // 13056 Muestras de sacrificio
)(
    input  logic        clk,
    input  logic        rst_n,      // Reset estándar AXI (Activo a nivel bajo)
    
    // =========================================================================
    // 1. INTERFAZ AXI4-STREAM ESCLAVA (Desde el ADC / Bob) -- input_pq
    // =========================================================================
    input  logic [31:0] s_axis_pq_tdata,   // Recibe {q_in, p_in} concatenados
    input  logic        s_axis_pq_tvalid,
    output logic        s_axis_pq_tready,  // Avisa si el HW está listo para recibir
    
    // =========================================================================
    // 2. INTERFAZ AXI4-STREAM ESCLAVA (Recepción desde Alice)
    // =========================================================================
    input  logic [31:0] s_axis_alice_tdata,
    input  logic        s_axis_alice_tvalid,
    output logic        s_axis_alice_tready,
    
    // (Mantenidas sueltas temporalmente, pueden ir a pines físicos o AXI GPIO)
    input  logic        mask_valid,
    input  logic        mask_bit,
    
    // =========================================================================
    // 3. INTERFAZ TRNG (Generador de Números Aleatorios)
    // =========================================================================
    input  logic [7:0]  trng_data,         
    
    // =========================================================================
    // 4. INTERFAZ AXI4-LITE / PUERTOS DE REGISTRO (Hacia el Procesador)
    // =========================================================================
    input  logic signed [31:0] calib_VarA,
    output logic signed [31:0] T_final_out,
    output logic signed [31:0] T_sqrt_out,
    output logic signed [31:0] sigma_sq_out,
    output logic signed [31:0] sigma_out,
    output logic [31:0]        num_samples_out,
    output logic               done_est,
    
    // =========================================================================
    // 5. INTERFAZ AXI4-STREAM MAESTRA (Hacia CPU - MDR para reconciliar)
    // =========================================================================
    output logic [255:0] m_axis_mdr_tdata,
    output logic         m_axis_mdr_tvalid,
    input  logic         m_axis_mdr_tready,
    output logic         m_axis_mdr_tlast,  // Marca el final de un bloque MDR
    
    // =========================================================================
    // 6. INTERFAZ AXI4-STREAM MAESTRA (Hacia CPU - Síndrome LDPC)
    // =========================================================================
    output logic [383:0] m_axis_syndrome_tdata,
    output logic         m_axis_syndrome_tvalid,
    input  logic         m_axis_syndrome_tready,
    output logic         m_axis_syndrome_tlast  // Dispara la interrupción del DMA
);

    // =========================================================================
    // ADAPTADOR DE RESET Y MANEJO DE BUSES AXI-STREAM
    // =========================================================================
    logic rst;
    assign rst = ~rst_n; // El DSP y el Router usan reset a nivel alto

    // --- Desempaquetado de buses de entrada (Esclavos) ---
    logic signed [ADC_WIDTH-1:0] p_in;
    logic signed [ADC_WIDTH-1:0] q_in;
    logic                        valid_in;

    // Asumimos que la CPU empaqueta p_in en los bits bajos y q_in en los altos (o viceversa)
    assign p_in     = s_axis_pq_tdata[ADC_WIDTH-1:0];
    assign q_in     = s_axis_pq_tdata[2*ADC_WIDTH-1:ADC_WIDTH];
    assign valid_in = s_axis_pq_tvalid;
    
    // Control de flujo: ponemos 'ready' a 1 indicando que el HW siempre puede recibir.
    // (Si tus módulos internos necesitan pausarse, tendrías que conectar esto a su lógica).
    assign s_axis_pq_tready    = 1'b1;
    assign s_axis_alice_tready = 1'b1;

    logic alice_stream_valid;
    logic [31:0] alice_stream_data;
    
    assign alice_stream_data  = s_axis_alice_tdata;
    assign alice_stream_valid = s_axis_alice_tvalid;

    // --- Control de señales tlast para buses de salida (Maestros) ---
    
    // Si el MDR se envía en una única transacción de 256 bits, el último dato es también el primero.
    assign m_axis_mdr_tlast = m_axis_mdr_tvalid; 
    
    // Para el síndrome, la señal 'syndrome_done' interna es perfecta para mapearla a 'tlast'
    logic syndrome_done_internal;
    assign m_axis_syndrome_tlast = syndrome_done_internal;

    // =========================================================================
    // CABLES INTERNOS DE ENRUTAMIENTO
    // =========================================================================
    logic signed [ADC_WIDTH-1:0] dsp_p_out;
    logic signed [ADC_WIDTH-1:0] dsp_q_out;
    logic                        dsp_valid_out;
    logic [31:0]                 dsp_data_packed;
    
    logic        router_valid_sac;
    logic [31:0] router_data_sac;
    
    logic        valid_key;
    logic [31:0] data_key;

    assign dsp_data_packed = {dsp_q_out, dsp_p_out};

    // =========================================================================
    // BLOQUE 1: DSP (Recuperación de Fase Cuántica)
    // =========================================================================
    cvqkd_bob_dsp_top #(
        .ADC_WIDTH(ADC_WIDTH)
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
    // BLOQUE 2: ENRUTADOR (Mega-FIFO y criba de datos)
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
        .valid_key(valid_key),   
        .data_key(data_key)      
    );

    // =========================================================================
    // BLOQUE 3: ESTIMACIÓN DE PARÁMETROS
    // =========================================================================
    param_estimator_top #(
        .NUM_SAMPLES(NUM_SAMPLES)
    ) param_estimator_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(mask_valid),         
        .done(done_est),
        .bob_stream_valid(router_valid_sac),
        .bob_stream_data(router_data_sac),
        .alice_stream_valid(alice_stream_valid),
        .alice_stream_data(alice_stream_data),
        .calib_VarA(calib_VarA),
        .T_final_out(T_final_out),
        .sigma_sq_out(sigma_sq_out),
        .sigma_out(sigma_out),
        .num_samples_out(num_samples_out),
        .T_sqrt_out(T_sqrt_out)
    );

    // =========================================================================
    // BLOQUE 4: SUBSISTEMA DE RECONCILIACIÓN (MDR + Síndrome)
    // =========================================================================
    logic [5:0] syndrome_row_idx_open; // Señal no expuesta al exterior (AXI-Stream asume el orden implícito)

    cvqkd_reconciliation_top reconciliation_inst (
        .clk(clk),
        .rst_n(rst_n),
        .router_valid(valid_key),
        .router_data(data_key),
        .trng_data(trng_data),
        
        // MDR conectado directamente a las salidas maestras
        .mdr_valid(m_axis_mdr_tvalid),
        .mdr_m_out(m_axis_mdr_tdata),
        
        // Síndrome conectado directamente a las salidas maestras
        .syndrome_done(syndrome_done_internal),
        .syndrome_valid(m_axis_syndrome_tvalid),
        .syndrome_row_idx(syndrome_row_idx_open), 
        .syndrome_data(m_axis_syndrome_tdata)
    );

endmodule