`timescale 1ns / 1ps
// =============================================================================
// Top-Level AXI Wrapper para el Subsistema Bob CV-QKD
// Integra:
//   - AXI4-Lite Slave: Registros de control, calibracion y telemetria
//   - AXI4-Stream Slave 's_axis_pq': Datos recibidos del ADC Bob {Q[15:0], P[15:0]}
//   - AXI4-Stream Slave 's_axis_alice': Datos clasicos de sacrificio de Alice (32 bits)
//   - AXI4-Stream Slave 's_axis_mask': Mascara de sacrificio empaquetada (32 bits/palabra)
//     con deserializador 32:1 hacia mask_valid y mask_bit
//   - AXI4-Stream Master 'm_axis_mdr': Mensajes publicos MDR (256 bits)
//   - AXI4-Stream Master 'm_axis_syndrome': Sindrome LDPC hacia CPU/DMA (512 bits)
// =============================================================================

module cvqkd_bob_axi_wrapper #(
    parameter integer ADC_WIDTH           = 16,
    parameter integer NUM_SAMPLES         = 26112/2, // 13056 muestras de sacrificio
    parameter integer C_S_AXI_DATA_WIDTH  = 32,
    parameter integer C_S_AXI_ADDR_WIDTH  = 5        // 8 registros de 32 bits (0x00 - 0x1C)
)(
    // Reloj y Reset globales (AXI estándar)
    input  wire                                 aclk,
    input  wire                                 aresetn,

    // =========================================================================
    // 1. INTERFAZ AXI4-LITE SLAVE (Control y Registros)
    // =========================================================================
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]        s_axi_awaddr,
    input  wire [2:0]                           s_axi_awprot,
    input  wire                                 s_axi_awvalid,
    output wire                                 s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]        s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]    s_axi_wstrb,
    input  wire                                 s_axi_wvalid,
    output wire                                 s_axi_wready,
    output wire [1:0]                           s_axi_bresp,
    output wire                                 s_axi_bvalid,
    input  wire                                 s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]        s_axi_araddr,
    input  wire [2:0]                           s_axi_arprot,
    input  wire                                 s_axi_arvalid,
    output wire                                 s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0]        s_axi_rdata,
    output wire [1:0]                           s_axi_rresp,
    output wire                                 s_axi_rvalid,
    input  wire                                 s_axi_rready,

    // =========================================================================
    // 2. INTERFAZ AXI4-STREAM SLAVE (Muestras ADC Bob {Q, P})
    // =========================================================================
    input  wire [31:0]                          s_axis_pq_tdata,
    input  wire                                 s_axis_pq_tvalid,
    output wire                                 s_axis_pq_tready,
    input  wire                                 s_axis_pq_tlast,

    // =========================================================================
    // 3. INTERFAZ AXI4-STREAM SLAVE (Muestras Sacrificio de Alice)
    // =========================================================================
    input  wire [31:0]                          s_axis_alice_tdata,
    input  wire                                 s_axis_alice_tvalid,
    output wire                                 s_axis_alice_tready,
    input  wire                                 s_axis_alice_tlast,

    // =========================================================================
    // 4. INTERFAZ AXI4-STREAM SLAVE (Mascara de Sacrificio empaquetada en 32b)
    // =========================================================================
    input  wire [31:0]                          s_axis_mask_tdata,
    input  wire                                 s_axis_mask_tvalid,
    output wire                                 s_axis_mask_tready,
    input  wire                                 s_axis_mask_tlast,

    // =========================================================================
    // 5. INTERFAZ AXI4-STREAM MASTER (Mensajes MDR - 256 bits)
    // =========================================================================
    output wire [255:0]                         m_axis_mdr_tdata,
    output wire                                 m_axis_mdr_tvalid,
    input  wire                                 m_axis_mdr_tready,
    output wire                                 m_axis_mdr_tlast,

    // =========================================================================
    // 6. INTERFAZ AXI4-STREAM MASTER (Sindrome LDPC - 512 bits)
    // =========================================================================
    output wire [511:0]                         m_axis_syndrome_tdata,
    output wire                                 m_axis_syndrome_tvalid,
    input  wire                                 m_axis_syndrome_tready,
    output wire                                 m_axis_syndrome_tlast
);

    // =========================================================================
    // REGISTROS INTERNOS AXI4-LITE
    // =========================================================================
    // 0x00: Control Register (bit 0: soft_reset, bit 1: enable)
    // 0x04: calib_VarA (Q16.16)
    // 0x08: Status Register (bit 0: done_est, bit 1: syndrome_done)
    // 0x0C: T_final_out
    // 0x10: T_sqrt_out
    // 0x14: sigma_sq_out
    // 0x18: sigma_out
    // 0x1C: num_samples_out
    
    reg [31:0] reg_ctrl;
    reg [31:0] reg_calib_vara;
    wire [31:0] reg_status;
    
    wire signed [31:0] T_final_out;
    wire signed [31:0] T_sqrt_out;
    wire signed [31:0] sigma_sq_out;
    wire signed [31:0] sigma_out;
    wire [31:0]        num_samples_out;
    wire               done_est;
    wire               syndrome_done;

    assign reg_status = {30'd0, syndrome_done, done_est};

    // --- Logica AXI4-Lite Slave Handshake ---
    reg axi_awready;
    reg axi_wready;
    reg axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    
    reg axi_arready;
    reg axi_rvalid;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;

    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_arready = axi_arready;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rvalid  = axi_rvalid;
    assign s_axi_rdata   = axi_rdata;

    // AXI-Lite Write Channel
    always @(posedge aclk) begin
        if (!aresetn) begin
            axi_awready    <= 1'b0;
            axi_wready     <= 1'b0;
            axi_bvalid     <= 1'b0;
            axi_awaddr     <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            reg_ctrl       <= 32'd2; // enable activo por defecto
            reg_calib_vara <= 32'd40000; // Calibracion nominal de Alice
        end else begin
            // Handshake AW
            if (~axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready <= 1'b1;
                axi_awaddr  <= s_axi_awaddr;
            end else begin
                axi_awready <= 1'b0;
            end

            // Handshake W
            if (~axi_wready && s_axi_wvalid && s_axi_awvalid) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end

            // Write Operation
            if (axi_awready && s_axi_awvalid && axi_wready && s_axi_wvalid) begin
                case (axi_awaddr[4:2])
                    3'b000: reg_ctrl       <= s_axi_wdata; // 0x00
                    3'b001: reg_calib_vara <= s_axi_wdata; // 0x04
                    default: ;
                endcase
            end

            // Handshake B
            if (axi_awready && s_axi_awvalid && axi_wready && s_axi_wvalid && ~axi_bvalid) begin
                axi_bvalid <= 1'b1;
            end else if (s_axi_bready && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // AXI-Lite Read Channel
    always @(posedge aclk) begin
        if (!aresetn) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= 32'd0;
            axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            // Handshake AR
            if (~axi_arready && s_axi_arvalid) begin
                axi_arready <= 1'b1;
                axi_araddr  <= s_axi_araddr;
            end else begin
                axi_arready <= 1'b0;
            end

            // Handshake R & Register Read Multiplexer
            if (axi_arready && s_axi_arvalid && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                case (axi_araddr[4:2])
                    3'b000: axi_rdata <= reg_ctrl;        // 0x00
                    3'b001: axi_rdata <= reg_calib_vara;  // 0x04
                    3'b010: axi_rdata <= reg_status;      // 0x08
                    3'b011: axi_rdata <= T_final_out;     // 0x0C
                    3'b100: axi_rdata <= T_sqrt_out;      // 0x10
                    3'b101: axi_rdata <= sigma_sq_out;    // 0x14
                    3'b110: axi_rdata <= sigma_out;       // 0x18
                    3'b111: axi_rdata <= num_samples_out; // 0x1C
                    default: axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rready && axi_rvalid) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // DESERIALIZADOR 32:1 DE LA MÁSCARA (s_axis_mask -> mask_valid, mask_bit)
    // =========================================================================
    // La CPU o el DMA envia palabras de 32 bits de mascara (816 palabras = 26112 bits).
    // Cada bit determina si una muestra se sacrifica (1) o se usa para clave (0).
    // Este bloque extrae 1 bit por ciclo (LSB primero).
    // =========================================================================
    reg [31:0] mask_shift_reg;
    reg [5:0]  mask_bits_rem; // 0 a 32
    reg        mask_valid_int;
    reg        mask_bit_int;
    reg        mask_axis_tready;

    assign s_axis_mask_tready = mask_axis_tready;

    always @(posedge aclk) begin
        if (!aresetn || reg_ctrl[0]) begin
            mask_shift_reg   <= 32'd0;
            mask_bits_rem    <= 6'd0;
            mask_valid_int   <= 1'b0;
            mask_bit_int     <= 1'b0;
            mask_axis_tready <= 1'b1; // Listo para capturar la primera palabra
        end else begin
            if (mask_bits_rem == 6'd0) begin
                // Estamos esperando una palabra nueva
                mask_axis_tready <= 1'b1;
                if (s_axis_mask_tvalid && mask_axis_tready) begin
                    mask_bit_int     <= s_axis_mask_tdata[0];
                    mask_shift_reg   <= {1'b0, s_axis_mask_tdata[31:1]};
                    mask_valid_int   <= 1'b1;
                    mask_bits_rem    <= 6'd31;
                    mask_axis_tready <= 1'b0;
                end else begin
                    mask_valid_int   <= 1'b0;
                end
            end else if (mask_bits_rem == 6'd1) begin
                // Ultimo bit de la palabra actual: extraemos y habilitamos tready para no perder ciclo
                mask_bit_int   <= mask_shift_reg[0];
                mask_valid_int <= 1'b1;
                mask_bits_rem  <= 6'd0;
                mask_axis_tready <= 1'b1;
                
                // Si la siguiente palabra ya esta disponible, la capturamos inmediatamente
                if (s_axis_mask_tvalid) begin
                    mask_shift_reg   <= {1'b0, s_axis_mask_tdata[31:1]};
                    mask_bits_rem    <= 6'd31;
                    mask_axis_tready <= 1'b0;
                    mask_bit_int     <= s_axis_mask_tdata[0];
                end
            end else begin
                // Extrayendo bits intermedios de la palabra
                mask_bit_int     <= mask_shift_reg[0];
                mask_shift_reg   <= {1'b0, mask_shift_reg[31:1]};
                mask_valid_int   <= 1'b1;
                mask_bits_rem    <= mask_bits_rem - 1'b1;
                mask_axis_tready <= 1'b0;
            end
        end
    end

    // =========================================================================
    // GENERADOR TRNG INTERNO AUTÓNOMO (8 bits)
    // =========================================================================
    // Proporciona un flujo de bytes pseudoaleatorios continuo para el modulador MDR
    // evitando requerir pines físicos en la FPGA durante las pruebas.
    // =========================================================================
    reg [7:0] trng_reg;
    always @(posedge aclk) begin
        if (!aresetn || reg_ctrl[0]) begin
            trng_reg <= 8'hA5; // Semilla de arranque
        end else begin
            // LFSR de 8 bits con polinomio irreducible (x^8 + x^6 + x^5 + x^4 + 1)
            trng_reg <= {trng_reg[6:0], trng_reg[7] ^ trng_reg[5] ^ trng_reg[4] ^ trng_reg[3]};
        end
    end

    // =========================================================================
    // INSTANCIA DEL TOP DEL SUBSISTEMA CV-QKD BOB
    // =========================================================================
    cvqkd_bob_subsystem_top #(
        .ADC_WIDTH(ADC_WIDTH),
        .NUM_SAMPLES(NUM_SAMPLES)
    ) u_cvqkd_bob_subsystem (
        .clk                    (aclk),
        .rst_n                  (aresetn && !reg_ctrl[0]),
        
        // Entrada AXI-Stream ADC Bob
        .s_axis_pq_tdata        (s_axis_pq_tdata),
        .s_axis_pq_tvalid       (s_axis_pq_tvalid),
        .s_axis_pq_tready       (s_axis_pq_tready),
        
        // Entrada AXI-Stream Sacrificio Alice
        .s_axis_alice_tdata     (s_axis_alice_tdata),
        .s_axis_alice_tvalid    (s_axis_alice_tvalid),
        .s_axis_alice_tready    (s_axis_alice_tready),
        
        // Máscara generada por el deserializador
        .mask_valid             (mask_valid_int),
        .mask_bit               (mask_bit_int),
        
        // TRNG interno
        .trng_data              (trng_reg),
        
        // Registros AXI4-Lite
        .calib_VarA             (reg_calib_vara),
        .T_final_out            (T_final_out),
        .T_sqrt_out             (T_sqrt_out),
        .sigma_sq_out           (sigma_sq_out),
        .sigma_out              (sigma_out),
        .num_samples_out        (num_samples_out),
        .done_est               (done_est),
        
        // Salida AXI-Stream MDR
        .m_axis_mdr_tdata       (m_axis_mdr_tdata),
        .m_axis_mdr_tvalid      (m_axis_mdr_tvalid),
        .m_axis_mdr_tready      (m_axis_mdr_tready),
        .m_axis_mdr_tlast       (m_axis_mdr_tlast),
        
        // Salida AXI-Stream Síndrome
        .m_axis_syndrome_tdata  (m_axis_syndrome_tdata),
        .m_axis_syndrome_tvalid (m_axis_syndrome_tvalid),
        .m_axis_syndrome_tready (m_axis_syndrome_tready),
        .m_axis_syndrome_tlast  (m_axis_syndrome_tlast)
    );

endmodule
