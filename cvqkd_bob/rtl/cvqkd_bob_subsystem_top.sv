`timescale 1ns / 1ps

module cvqkd_bob_subsystem_top #(
    parameter ADC_WIDTH   = 16,
    parameter NUM_SAMPLES = 26112/2, // 13056 Muestras de sacrificio
    parameter MDR_BLOCKS  = 3264     // Bloques 8D (mensajes MDR) por trama
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

    // Máscara de sacrificio (desde el deserializador del wrapper)
    input  logic        mask_valid,
    input  logic        mask_bit,

    // =========================================================================
    // 3. CLAVE ALEATORIA DE BOB (memoria precargada en el wrapper)
    // =========================================================================
    input  logic [7:0]  trng_data,
    input  logic        key_enable,        // 0 = no hay clave sin usar: no se reconcilia

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
    output logic               syndrome_done,
    output logic               data_loss,  // Sticky: se ha perdido algún dato de la trama

    // =========================================================================
    // 5. INTERFAZ AXI4-STREAM MAESTRA (Hacia CPU - MDR para reconciliar)
    // =========================================================================
    output logic [255:0] m_axis_mdr_tdata,
    output logic         m_axis_mdr_tvalid,
    input  logic         m_axis_mdr_tready,
    output logic         m_axis_mdr_tlast,  // Último mensaje MDR de la trama

    // =========================================================================
    // 6. INTERFAZ AXI4-STREAM MAESTRA (Hacia CPU - Síndrome LDPC)
    // =========================================================================
    output logic [511:0] m_axis_syndrome_tdata,
    output logic         m_axis_syndrome_tvalid,
    input  logic         m_axis_syndrome_tready,
    output logic         m_axis_syndrome_tlast,  // Última fila: dispara la interrupción del DMA

    // Señal interna hacia el wrapper: pulso para avanzar el puntero de clave
    output logic         trng_req
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

    // La CPU empaqueta p_in en los bits bajos y q_in en los altos
    assign p_in     = s_axis_pq_tdata[ADC_WIDTH-1:0];
    assign q_in     = s_axis_pq_tdata[2*ADC_WIDTH-1:ADC_WIDTH];
    assign valid_in = s_axis_pq_tvalid;

    // Control de flujo: ponemos 'ready' a 1 para ADC (el FIFO del router almacena la trama).
    // Para Alice, conectamos el ready al estado de su FIFO en el estimador de parametros.
    assign s_axis_pq_tready = 1'b1;

    // =========================================================================
    // CABLES INTERNOS DE ENRUTAMIENTO
    // =========================================================================
    logic signed [ADC_WIDTH-1:0] dsp_p_out;
    logic signed [ADC_WIDTH-1:0] dsp_q_out;
    logic                        dsp_valid_out;

    logic        router_valid_sac;
    logic [31:0] router_data_sac;
    logic        valid_key;
    logic [31:0] data_key;

    logic         mdr_valid;
    logic [255:0] mdr_data;
    logic         syndrome_valid;
    logic [5:0]   syndrome_row_idx;
    logic [383:0] syndrome_data;

    logic router_loss, estimator_overflow, mdr_overflow, syndrome_overflow, key_missing;

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
        .dsp_data({dsp_q_out, dsp_p_out}),
        .mask_valid(mask_valid),
        .mask_bit(mask_bit),
        .valid_sac(router_valid_sac),
        .data_sac(router_data_sac),
        .valid_key(valid_key),
        .data_key(data_key),
        .data_loss(router_loss)
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
        .alice_stream_valid(s_axis_alice_tvalid),
        .alice_stream_data(s_axis_alice_tdata),
        .alice_stream_ready(s_axis_alice_tready),
        .calib_VarA(calib_VarA),
        .T_final_out(T_final_out),
        .sigma_sq_out(sigma_sq_out),
        .sigma_out(sigma_out),
        .num_samples_out(num_samples_out),
        .T_sqrt_out(T_sqrt_out),
        .overflow(estimator_overflow)
    );

    // =========================================================================
    // BLOQUE 4: SUBSISTEMA DE RECONCILIACIÓN (MDR + Síndrome)
    // =========================================================================
    // Sin clave sin usar no se reconcilia: reutilizar los bits de Bob rompería la seguridad.
    cvqkd_reconciliation_top reconciliation_inst (
        .clk(clk),
        .rst_n(rst_n),
        .router_valid(valid_key && key_enable),
        .router_data(data_key),
        .trng_data(trng_data),
        .mdr_valid(mdr_valid),
        .mdr_m_out(mdr_data),
        .syndrome_done(syndrome_done),
        .syndrome_valid(syndrome_valid),
        .syndrome_row_idx(syndrome_row_idx),
        .syndrome_data(syndrome_data),
        .trng_req(trng_req)
    );

    // =========================================================================
    // BLOQUE 5: BUFFERS DE SALIDA AXI4-STREAM (respetan tready)
    // =========================================================================
    // TLAST del MDR solo en el último bloque de la trama: el DMA recibe la trama
    // completa en una única transferencia.
    logic [$clog2(MDR_BLOCKS)-1:0] mdr_blk_cnt;
    logic                          mdr_last;

    assign mdr_last = (mdr_blk_cnt == MDR_BLOCKS - 1);

    always_ff @(posedge clk) begin
        if (rst) begin
            mdr_blk_cnt <= '0;
        end else if (mdr_valid) begin
            mdr_blk_cnt <= mdr_last ? '0 : mdr_blk_cnt + 1'b1;
        end
    end

    axis_out_fifo #(
        .DATA_WIDTH(256),
        .DEPTH(64)
    ) mdr_out_fifo (
        .clk(clk),
        .rst(rst),
        .s_valid(mdr_valid),
        .s_data(mdr_data),
        .s_last(mdr_last),
        .m_tdata(m_axis_mdr_tdata),
        .m_tvalid(m_axis_mdr_tvalid),
        .m_tready(m_axis_mdr_tready),
        .m_tlast(m_axis_mdr_tlast),
        .overflow(mdr_overflow)
    );

    // Caben las 46 filas del síndrome: no se pierde nada aunque el DMA se arme tarde.
    // El bus de 512 bits es el ancho de stream del AXI DMA más cercano a 384.
    logic [383:0] m_axis_syndrome_row;
    assign m_axis_syndrome_tdata = {128'd0, m_axis_syndrome_row};

    axis_out_fifo #(
        .DATA_WIDTH(384),
        .DEPTH(64)
    ) syndrome_out_fifo (
        .clk(clk),
        .rst(rst),
        .s_valid(syndrome_valid),
        .s_data(syndrome_data),
        .s_last(syndrome_row_idx == 6'd45),
        .m_tdata(m_axis_syndrome_row),
        .m_tvalid(m_axis_syndrome_tvalid),
        .m_tready(m_axis_syndrome_tready),
        .m_tlast(m_axis_syndrome_tlast),
        .overflow(syndrome_overflow)
    );

    // =========================================================================
    // DIAGNÓSTICO: cualquier pérdida de datos invalida la trama
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst)                          key_missing <= 1'b0;
        else if (valid_key && !key_enable) key_missing <= 1'b1;
    end

    assign data_loss = router_loss || estimator_overflow || mdr_overflow
                    || syndrome_overflow || key_missing;

endmodule
