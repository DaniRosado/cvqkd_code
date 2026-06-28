`timescale 1ns / 1ps

module cvqkd_bob_subsystem_top #(
    parameter ADC_WIDTH   = 16,
    parameter NUM_SAMPLES = 26112/2 // 13056 Muestras de sacrificio
)(
    input  logic        clk,
    input  logic        rst_n,      // Reset estándar AXI (Activo a nivel bajo)
    
    // =========================================================================
    // 1. INTERFAZ FÍSICA (Desde el ADC / Canal Cuántico)
    // =========================================================================
    input  logic signed [ADC_WIDTH-1:0] p_in,
    input  logic signed [ADC_WIDTH-1:0] q_in,
    input  logic                        valid_in,
    
    // =========================================================================
    // 2. INTERFAZ DE RED CLÁSICA (Recepción desde Alice)
    // =========================================================================
    input  logic                        mask_valid,
    input  logic                        mask_bit,
    input  logic                        alice_stream_valid,
    input  logic [31:0]                 alice_stream_data,   // {Q_Alice, P_Alice}
    
    // =========================================================================
    // 3. INTERFAZ TRNG (Generador de Números Aleatorios)
    // =========================================================================
    input  logic [7:0]                  trng_data,           // 8 bits aleatorios por ciclo
    
    // =========================================================================
    // 4. INTERFAZ AXI4-LITE (Hacia el Procesador ARM / Vitis)
    // =========================================================================
    // Entradas (Escritas por la CPU)
    input  logic signed [31:0]          calib_VarA,          // Varianza calibrada
    input  logic                        skr_valid,           // La CPU confirma que escribió el SKR
    input  logic signed [31:0]          skr_in,              // Valor exacto del SKR calculado en C
    
    // Salidas (Leídas por la CPU)
    output logic signed [31:0]          T_final_out,
    output logic signed [31:0]          sigma_sq_out,
    output logic signed [31:0]          sigma_out,
    output logic [31:0]                 num_samples_out,
    
    // Señales de Interrupción y Estado
    output logic                        irq,                 // Aviso a la CPU: "Estimación lista"
    output logic                        done_est,            // (Opcional) Fin de ciclo del estimador
    
    // =========================================================================
    // 5. INTERFACES DE TRANSMISIÓN (Hacia fuera del chip / Alice / Monitorización)
    // =========================================================================
    // A. Señales Globales de Seguridad
    output logic                        frame_valid_out,     // 1 = Segura, 0 = Comprometida
    output logic signed [31:0]          T_sqrt_out,          // Para el destilador de Alice
    output logic signed [31:0]          skr_out,             // SKR propagado al resto del HW
    
    // B. Hacia Alice (Mensajes Públicos MDR para reconciliar)
    output logic                        mdr_valid,
    output logic [255:0]                mdr_m_out,
    
    // C. Hacia Procesador/AXI-Stream (Síndrome para decodificar LDPC)
    output logic                        syndrome_done,
    output logic [383:0]                syndrome_out [0:45]
);

    // =========================================================================
    // ADAPTADOR DE RESET PARA MÓDULOS ANTIGUOS
    // =========================================================================
    logic rst;
    assign rst = ~rst_n; // El DSP y el Router usan reset a nivel alto

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

    // Empaquetado del bus del DSP para el Router
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
    // BLOQUE 3: ESTIMACIÓN DE PARÁMETROS (Hardware <-> Software)
    // =========================================================================
    param_estimator_top #(
        .NUM_SAMPLES(NUM_SAMPLES)
    ) param_estimator_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(mask_valid),         // La estimación arranca cuando empieza a llegar la máscara
        .done(done_est),
        
        // Entradas de Datos (Streaming)
        .bob_stream_valid(router_valid_sac),
        .bob_stream_data(router_data_sac),
        .alice_stream_valid(alice_stream_valid),
        .alice_stream_data(alice_stream_data),
        
        // Interfaz AXI (CPU -> HW)
        .calib_VarA(calib_VarA),
        .skr_valid(skr_valid),
        .skr_in(skr_in),
        
        // Interfaz AXI (HW -> CPU)
        .T_final_out(T_final_out),
        .sigma_sq_out(sigma_sq_out),
        .sigma_out(sigma_out),
        .num_samples_out(num_samples_out),
        .irq(irq),
        
        // Salidas Hardware Globales
        .frame_valid_out(frame_valid_out),
        .T_sqrt_out(T_sqrt_out),
        .skr_out(skr_out)
    );

    // =========================================================================
    // BLOQUE 4: SUBSISTEMA DE RECONCILIACIÓN (MDR + Síndrome)
    // =========================================================================
    cvqkd_reconciliation_top reconciliation_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // Ingesta de datos de la clave desde el Router
        .router_valid(valid_key),
        .router_data(data_key),
        .trng_data(trng_data),
        
        // Salidas públicas
        .mdr_valid(mdr_valid),
        .mdr_m_out(mdr_m_out),
        .syndrome_done(syndrome_done),
        .syndrome_out(syndrome_out)
    );

endmodule