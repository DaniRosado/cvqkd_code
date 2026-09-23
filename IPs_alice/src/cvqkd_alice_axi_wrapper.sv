`timescale 1ns / 1ps

// ============================================================================
// Módulo:       cvqkd_alice_axi_wrapper
// Proyecto:     CV-QKD Hardware Accelerator - Subsistema Alice
// Descripción:  Wrapper AXI4-Lite y AXI4-Stream que encapsula el subsistema
//               completo de post-procesamiento de Alice (MDR + LDPC Decoder).
//               Permite al procesador ARM (Zynq PS):
//               - Inyectar coordenadas X y mensaje m mediante AXI DMA (MM2S).
//               - Configurar factor K y escribir el síndrome objetivo de Bob.
//               - Leer la clave secreta reconciliada b_hat directamente por AXI-Lite.
// ============================================================================

module cvqkd_alice_axi_wrapper #(
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 13, // 8 KB ventana (0x0000 - 0x1FFF)
    parameter int TOTAL_BLOCKS       = 3264,
    parameter int Z                  = 384,
    parameter int W                  = 8
)(
    input  wire                                aclk,
    input  wire                                aresetn,

    // =========================================================================
    // 1. INTERFAZ AXI4-LITE ESCLAVA (Control, Estado y Memorias BRAM)
    // =========================================================================
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       s_axi_awaddr,
    input  wire                                s_axi_awvalid,
    output wire                                s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]       s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]   s_axi_wstrb,
    input  wire                                s_axi_wvalid,
    output wire                                s_axi_wready,
    output wire [1:0]                          s_axi_bresp,
    output wire                                s_axi_bvalid,
    input  wire                                s_axi_bready,
    
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       s_axi_araddr,
    input  wire                                s_axi_arvalid,
    output wire                                s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0]       s_axi_rdata,
    output wire [1:0]                          s_axi_rresp,
    output wire                                s_axi_rvalid,
    input  wire                                s_axi_rready,

    // =========================================================================
    // 2. INTERFAZ AXI4-STREAM ESCLAVA 0: Coordenadas X de Alice (desde DMA 0)
    // =========================================================================
    input  wire [31:0]                         s_axis_x_tdata,
    input  wire                                s_axis_x_tvalid,
    output wire                                s_axis_x_tready,
    input  wire                                s_axis_x_tlast,

    // =========================================================================
    // 3. INTERFAZ AXI4-STREAM ESCLAVA 1: Mensaje m de Bob (desde DMA 1)
    // =========================================================================
    input  wire [31:0]                         s_axis_m_tdata,
    input  wire                                s_axis_m_tvalid,
    output wire                                s_axis_m_tready,
    input  wire                                s_axis_m_tlast
);

    // =========================================================================
    // REGISTROS DE CONTROL Y ESTADO
    // =========================================================================
    // 0x00: reg_ctrl   [0: soft_reset, 1: start_mdr, 2: start_ldpc, 3: auto_run]
    // 0x04: reg_status [0: mdr_done, 1: ldpc_done, 2: ldpc_success, 3: key_ready, 4: busy]
    // 0x08: reg_k_factor (Formato Q10)
    // 0x0C: reg_k_mode   (0: estático reg_k_factor, 1: dinámico ram_k)
    // 0x10: reg_x_blocks_rx (bloques X recibidos por DMA)
    // 0x14: reg_m_blocks_rx (bloques m recibidos por DMA)
    // =========================================================================
    reg [31:0] reg_ctrl;
    reg [31:0] reg_k_factor;
    reg [31:0] reg_k_mode;
    reg [13:0] reg_x_blocks_rx;
    reg [13:0] reg_m_blocks_rx;

    wire soft_reset = reg_ctrl[0];
    wire auto_run   = reg_ctrl[3];

    // Señales de control del core
    reg  start_mdr_pulse;
    reg  start_ldpc_pulse;
    wire mdr_done_sig;
    wire ldpc_done_sig;
    wire ldpc_success_sig;

    reg  mdr_done_latched;
    reg  ldpc_done_latched;
    reg  ldpc_success_latched;
    reg  key_ready_latched;
    reg  core_busy;

    wire [31:0] reg_status = {27'd0, core_busy, key_ready_latched, ldpc_success_latched, ldpc_done_latched, mdr_done_latched};

    // =========================================================================
    // MEMORIAS BRAM DE ENTRADA (X, m, K)
    // =========================================================================
    // ram_x: 3.264 bloques x 128 bits (16 bytes = 4 palabras de 32b)
    (* ram_style = "block" *) reg [127:0] ram_x [0:TOTAL_BLOCKS-1];
    
    // ram_m: 3.264 bloques x 256 bits (32 bytes = 8 palabras de 32b)
    (* ram_style = "block" *) reg [255:0] ram_m [0:TOTAL_BLOCKS-1];

    // ram_k: 3.264 palabras de 32 bits (fallback inicializado desde archivo)
    (* ram_style = "block" *) reg [31:0]  ram_k [0:TOTAL_BLOCKS-1];
    initial begin
        $readmemh("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/alice_k_dynamic.txt", ram_k);
    end

    // =========================================================================
    // MEMORIA DE SÍNDROME OBJETIVO DE BOB (46 filas x 384 bits = 552 palabras de 32b)
    // Mapeada en AXI-Lite: 0x100 a 0x99C
    // =========================================================================
    reg [383:0] target_syn_rows [0:45];
    initial begin
        $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_syndrome.txt", target_syn_rows);
    end

    // =========================================================================
    // MEMORIA DE CLAVE RECONCILIADA b_hat (68 columnas x 384 bits = 26.112 bits)
    // Mapeada en AXI-Lite: 0xA00 a 0x16BC (Lectura por ARM)
    // =========================================================================
    reg [383:0] key_hat_cols [0:67];

    // =========================================================================
    // HANDSHAKE AXI-LITE SLAVE
    // =========================================================================
    reg axi_awready, axi_wready, axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg axi_arready, axi_rvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;

    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_arready = axi_arready;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rvalid  = axi_rvalid;
    assign s_axi_rdata   = axi_rdata;

    wire is_syn_wr = (axi_awaddr >= 13'h0100) && (axi_awaddr < 13'h09A0);
    wire [9:0] syn_wr_idx = (axi_awaddr - 13'h0100) >> 2;

    wire is_syn_rd = (axi_araddr >= 13'h0100) && (axi_araddr < 13'h09A0);
    wire [9:0] syn_rd_idx = (axi_araddr - 13'h0100) >> 2;

    wire is_key_rd = (axi_araddr >= 13'h0A00) && (axi_araddr < 13'h16C0);
    wire [9:0] key_rd_idx = (axi_araddr - 13'h0A00) >> 2;

    always @(posedge aclk) begin
        if (!aresetn) begin
            axi_awready      <= 1'b0;
            axi_wready       <= 1'b0;
            axi_bvalid       <= 1'b0;
            axi_awaddr       <= '0;
            reg_ctrl         <= 32'd0;
            reg_k_factor     <= 32'd38; // Valor nominal aproximado en Q10
            reg_k_mode       <= 32'd1;  // Por defecto dinámico para testbenches
            start_mdr_pulse  <= 1'b0;
            start_ldpc_pulse <= 1'b0;
        end else begin
            start_mdr_pulse  <= 1'b0;
            start_ldpc_pulse <= 1'b0;

            // AW Channel
            if (~axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready <= 1'b1;
                axi_awaddr  <= s_axi_awaddr;
            end else begin
                axi_awready <= 1'b0;
            end

            // W Channel
            if (~axi_wready && s_axi_wvalid && s_axi_awvalid) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end

            // Write Execution
            if (axi_awready && s_axi_awvalid && axi_wready && s_axi_wvalid) begin
                if (is_syn_wr && (syn_wr_idx < 552)) begin
                    target_syn_rows[syn_wr_idx / 12][(syn_wr_idx % 12)*32 +: 32] <= s_axi_wdata;
                end else if (axi_awaddr < 13'h0100) begin
                    case (axi_awaddr[7:2])
                        6'h00: begin // 0x00: REG_CTRL
                            reg_ctrl <= s_axi_wdata;
                            if (s_axi_wdata[1]) start_mdr_pulse  <= 1'b1;
                            if (s_axi_wdata[2]) start_ldpc_pulse <= 1'b1;
                        end
                        6'h02: reg_k_factor <= s_axi_wdata; // 0x08
                        6'h03: reg_k_mode   <= s_axi_wdata; // 0x0C
                        default: ;
                    endcase
                end
            end

            // B Channel
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
            axi_araddr  <= '0;
        end else begin
            if (~axi_arready && s_axi_arvalid) begin
                axi_arready <= 1'b1;
                axi_araddr  <= s_axi_araddr;
            end else begin
                axi_arready <= 1'b0;
            end

            if (axi_arready && s_axi_arvalid && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                if (is_syn_rd && (syn_rd_idx < 552)) begin
                    axi_rdata <= target_syn_rows[syn_rd_idx / 12][(syn_rd_idx % 12)*32 +: 32];
                end else if (is_key_rd && (key_rd_idx < 816)) begin
                    axi_rdata <= key_hat_cols[key_rd_idx / 12][(key_rd_idx % 12)*32 +: 32];
                end else if (axi_araddr < 13'h0100) begin
                    case (axi_araddr[7:2])
                        6'h00: axi_rdata <= reg_ctrl;
                        6'h01: axi_rdata <= reg_status;
                        6'h02: axi_rdata <= reg_k_factor;
                        6'h03: axi_rdata <= reg_k_mode;
                        6'h04: axi_rdata <= {18'd0, reg_x_blocks_rx};
                        6'h05: axi_rdata <= {18'd0, reg_m_blocks_rx};
                        default: axi_rdata <= 32'd0;
                    endcase
                end else begin
                    axi_rdata <= 32'd0;
                end
            end else if (s_axi_rready && axi_rvalid) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // DESERIALIZADOR Y RECEPTOR DE COORDENADAS X (s_axis_x: 32b -> 128b)
    // 4 beats de 32 bits = 1 bloque de 128 bits (8 coordenadas de 16b)
    // =========================================================================
    reg [95:0] x_pack_reg;
    reg [1:0]  x_beat_cnt;
    assign s_axis_x_tready = 1'b1; // Siempre listo para recibir

    always @(posedge aclk) begin
        if (!aresetn || soft_reset) begin
            x_beat_cnt      <= 2'd0;
            x_pack_reg      <= 96'd0;
            reg_x_blocks_rx <= 14'd0;
        end else if (s_axis_x_tvalid) begin
            if (x_beat_cnt == 2'd3) begin
                ram_x[reg_x_blocks_rx] <= {s_axis_x_tdata, x_pack_reg};
                reg_x_blocks_rx        <= reg_x_blocks_rx + 1;
                x_beat_cnt             <= 2'd0;
            end else begin
                x_pack_reg[(x_beat_cnt * 32) +: 32] <= s_axis_x_tdata;
                x_beat_cnt                          <= x_beat_cnt + 1;
            end
        end
    end

    // =========================================================================
    // DESERIALIZADOR Y RECEPTOR DE MENSAJES m (s_axis_m: 32b -> 256b)
    // 8 beats de 32 bits = 1 bloque de 256 bits (8 coordenadas Q24)
    // =========================================================================
    reg [223:0] m_pack_reg;
    reg [2:0]   m_beat_cnt;
    assign s_axis_m_tready = 1'b1;

    always @(posedge aclk) begin
        if (!aresetn || soft_reset) begin
            m_beat_cnt      <= 3'd0;
            m_pack_reg      <= 224'd0;
            reg_m_blocks_rx <= 14'd0;
        end else if (s_axis_m_tvalid) begin
            if (m_beat_cnt == 3'd7) begin
                ram_m[reg_m_blocks_rx] <= {s_axis_m_tdata, m_pack_reg};
                reg_m_blocks_rx        <= reg_m_blocks_rx + 1;
                m_beat_cnt             <= 3'd0;
            end else begin
                m_pack_reg[(m_beat_cnt * 32) +: 32] <= s_axis_m_tdata;
                m_beat_cnt                          <= m_beat_cnt + 1;
            end
        end
    end

    // =========================================================================
    // CONEXIONES CON EL CORE DE POST-PROCESAMIENTO DE ALICE
    // =========================================================================
    wire        ram_x_en;
    wire [13:0] ram_x_addr;
    reg [127:0] ram_x_data;
    reg [255:0] ram_m_data;
    reg [31:0]  ram_k_data;

    always @(posedge aclk) begin
        if (ram_x_en) begin
            ram_x_data <= ram_x[ram_x_addr];
            ram_m_data <= ram_m[ram_x_addr];
            ram_k_data <= (reg_k_mode == 32'd0) ? reg_k_factor : ram_k[ram_x_addr];
        end
    end

    // Conexión del Síndrome Objetivo hacia el core
    reg         target_syn_we_sig;
    reg [5:0]   target_syn_addr_sig;
    reg [383:0] target_syn_data_sig;

    // Extracción de clave desde el LDPC hacia key_hat_cols
    reg         key_read_en_sig;
    reg [6:0]   key_read_addr_sig;
    wire [383:0] key_read_data_sig;

    // =========================================================================
    // FSM MAESTRA DE CONTROL Y EXTRACCIÓN DE CLAVE
    // =========================================================================
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_LOAD_SYN,
        ST_RUN_MDR,
        ST_WAIT_MDR,
        ST_RUN_LDPC,
        ST_WAIT_LDPC,
        ST_EXTRACT_KEY,
        ST_DONE
    } top_state_t;

    top_state_t state;
    reg [5:0]   syn_load_cnt;
    reg [6:0]   key_ext_col;
    reg         key_ext_valid;

    always @(posedge aclk) begin
        if (!aresetn || soft_reset) begin
            state                <= ST_IDLE;
            mdr_done_latched     <= 1'b0;
            ldpc_done_latched    <= 1'b0;
            ldpc_success_latched <= 1'b0;
            key_ready_latched    <= 1'b0;
            core_busy            <= 1'b0;
            target_syn_we_sig    <= 1'b0;
            target_syn_addr_sig  <= '0;
            target_syn_data_sig  <= '0;
            key_read_en_sig      <= 1'b0;
            key_read_addr_sig    <= '0;
            syn_load_cnt         <= '0;
            key_ext_col          <= '0;
            key_ext_valid        <= 1'b0;
        end else begin
            target_syn_we_sig <= 1'b0;
            key_read_en_sig   <= 1'b0;

            case (state)
                ST_IDLE: begin
                    core_busy <= 1'b0;
                    if (start_mdr_pulse || (auto_run && (reg_x_blocks_rx == TOTAL_BLOCKS) && (reg_m_blocks_rx == TOTAL_BLOCKS))) begin
                        mdr_done_latched     <= 1'b0;
                        ldpc_done_latched    <= 1'b0;
                        ldpc_success_latched <= 1'b0;
                        key_ready_latched    <= 1'b0;
                        core_busy            <= 1'b1;
                        syn_load_cnt         <= '0;
                        state                <= ST_LOAD_SYN;
                    end else if (start_ldpc_pulse) begin
                        ldpc_done_latched    <= 1'b0;
                        ldpc_success_latched <= 1'b0;
                        key_ready_latched    <= 1'b0;
                        core_busy            <= 1'b1;
                        syn_load_cnt         <= '0;
                        state                <= ST_LOAD_SYN;
                    end
                end

                // Carga las 46 filas de síndrome de Bob en el LDPC Decoder (46 ciclos)
                ST_LOAD_SYN: begin
                    target_syn_we_sig   <= 1'b1;
                    target_syn_addr_sig <= syn_load_cnt;
                    target_syn_data_sig <= target_syn_rows[syn_load_cnt];

                    if (syn_load_cnt == 6'd45) begin
                        if (start_ldpc_pulse) state <= ST_RUN_LDPC;
                        else                  state <= ST_RUN_MDR;
                    end else begin
                        syn_load_cnt <= syn_load_cnt + 1;
                    end
                end

                ST_RUN_MDR: begin
                    state <= ST_WAIT_MDR;
                end

                ST_WAIT_MDR: begin
                    if (mdr_done_sig) begin
                        mdr_done_latched <= 1'b1;
                        if (auto_run) state <= ST_RUN_LDPC;
                        else          state <= ST_DONE;
                    end
                end

                ST_RUN_LDPC: begin
                    state <= ST_WAIT_LDPC;
                end

                ST_WAIT_LDPC: begin
                    if (ldpc_done_sig) begin
                        ldpc_done_latched    <= 1'b1;
                        ldpc_success_latched <= ldpc_success_sig;
                        if (ldpc_success_sig) begin
                            key_ext_col       <= '0;
                            key_read_en_sig   <= 1'b1;
                            key_read_addr_sig <= '0;
                            key_ext_valid     <= 1'b0;
                            state             <= ST_EXTRACT_KEY;
                        end else begin
                            state <= ST_DONE;
                        end
                    end
                end

                // Extracción de las 68 columnas de la clave reconciliada desde L_BRAM
                ST_EXTRACT_KEY: begin
                    key_read_en_sig   <= 1'b1;
                    key_read_addr_sig <= key_ext_col;

                    if (key_ext_valid) begin
                        key_hat_cols[key_ext_col - 1] <= key_read_data_sig;
                    end

                    if (key_ext_col == 7'd68) begin
                        key_ready_latched <= 1'b1;
                        key_read_en_sig   <= 1'b0;
                        state             <= ST_DONE;
                    end else begin
                        key_ext_col   <= key_ext_col + 1;
                        key_ext_valid <= 1'b1;
                    end
                end

                ST_DONE: begin
                    core_busy <= 1'b0;
                    state     <= ST_IDLE;
                end
            endcase
        end
    end

    // Pulso de start hacia el MDR
    wire start_mdr_core  = (state == ST_RUN_MDR);
    // Pulso de start hacia el LDPC
    wire start_ldpc_core = (state == ST_RUN_LDPC);

    // =========================================================================
    // INSTANCIACIÓN DEL NÚCLEO COMPLETO DE ALICE
    // =========================================================================
    alice_post_processing_core #(
        .Z(Z),
        .W(W),
        .TOTAL_BLOCKS(TOTAL_BLOCKS)
    ) u_alice_core (
        .clk              (aclk),
        .rst_n            (aresetn && !soft_reset),
        
        .start_mdr        (start_mdr_core),
        .start_ldpc       (start_ldpc_core),
        .mdr_done         (mdr_done_sig),
        .ldpc_done        (ldpc_done_sig),
        .ldpc_success     (ldpc_success_sig),
        
        .ram_x_en         (ram_x_en),
        .ram_x_addr       (ram_x_addr),
        .ram_x_data       (ram_x_data),
        .ram_m_data       (ram_m_data),
        .ram_k_data       (ram_k_data),

        .target_syn_we    (target_syn_we_sig),
        .target_syn_addr  (target_syn_addr_sig),
        .target_syn_data  (target_syn_data_sig),

        .key_read_en      (key_read_en_sig),
        .key_read_addr    (key_read_addr_sig),
        .key_read_data    (key_read_data_sig)
    );

endmodule
