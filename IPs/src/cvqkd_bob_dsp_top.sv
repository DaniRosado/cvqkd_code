`timescale 1ns / 1ps

module cvqkd_bob_dsp_top #(
    parameter ADC_WIDTH = 16,
    parameter DSP_WIDTH = 18 // Formato expandido Q3.15 para los CORDIC
)(
    input  logic clk,
    input  logic rst,
    
    // Entradas desde el ADC (Alice)
    input  logic signed [ADC_WIDTH-1:0] p_in,
    input  logic signed [ADC_WIDTH-1:0] q_in,
    input  logic                        valid_in,
    
    // Salidas hacia la Memoria Principal (Bob)
    output logic signed [ADC_WIDTH-1:0] p_out,
    output logic signed [ADC_WIDTH-1:0] q_out,
    output logic                        valid_out
);

    // =========================================================================
    // 1. DECLARACIÓN DE CABLES INTERNOS (Wires)
    // =========================================================================
    
    // --- Cables del DEMUX ---
    logic [ADC_WIDTH*2-1:0] demux_to_cordic1_data;
    logic                   demux_to_cordic1_valid;
    logic [ADC_WIDTH*2-1:0] demux_to_fifo_data;
    logic                   demux_to_fifo_we;

    // --- Cables de la FIFO ---
    logic [ADC_WIDTH*2-1:0] fifo_to_cordic2_data;
    logic                   fifo_re;
    logic                   fifo_empty;
    logic                   fifo_full;

    // --- Cables del CORDIC 1 (Vectorización) ---
    logic [DSP_WIDTH-1:0]   cordic1_to_interp_theta;
    logic                   cordic1_to_interp_valid;

    // --- Cables del Interpolador (NUEVOS: Ya sincronizados y listos) ---
    logic [DSP_WIDTH-1:0]   interp_cordic_theta;
    logic                   interp_cordic_valid;

    // --- Cables del CORDIC 2 (Rotación) ---
    logic                   cordic2_to_gain_valid;

    // =========================================================================
    // 2. INSTANCIACIÓN DE LOS MÓDULOS (La Placa Base)
    // =========================================================================

    // 2.1. Framer / Demux
    demux_framer #(
        .DATA_WIDTH(ADC_WIDTH)
    ) inst_demux (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .p_in(p_in),
        .q_in(q_in),
        .m_axis_cordic_tdata(demux_to_cordic1_data),
        .m_axis_cordic_tvalid(demux_to_cordic1_valid),
        .fifo_data_out(demux_to_fifo_data),
        .fifo_we(demux_to_fifo_we)
    );

    // 2.2. FIFO de 64 posiciones
    sync_fifo #(
        .DATA_WIDTH(ADC_WIDTH * 2), // 32 bits
        .DEPTH(64)
    ) inst_fifo (
        .clk(clk),
        .rst(rst),
        .we(demux_to_fifo_we),
        .din(demux_to_fifo_data),
        .re(fifo_re),               // Viene directo del interpolador
        .dout(fifo_to_cordic2_data),
        .empty(fifo_empty),
        .full(fifo_full)
    );

    // 2.3. CORDIC 1: Vectorización (IP de Vivado)
    logic [47:0] cordic1_dout_tdata;

    cordic_vect_ip inst_cordic_vect (
        .aclk(clk),
        .s_axis_cartesian_tvalid(demux_to_cordic1_valid),
        .s_axis_cartesian_tdata({
            {8{demux_to_cordic1_data[31]}}, demux_to_cordic1_data[31:16], // Q
            {8{demux_to_cordic1_data[15]}}, demux_to_cordic1_data[15:0]   // P
        }),
        .m_axis_dout_tvalid(cordic1_to_interp_valid),
        .m_axis_dout_tdata(cordic1_dout_tdata) 
    );
    
    assign cordic1_to_interp_theta = cordic1_dout_tdata[41:24]; // Nos quedamos con los 18 bits útiles [41:24]
    
    // 2.4. El Cerebro: Interpolador de Fase
    phase_interpolator #(
        .THETA_WIDTH(DSP_WIDTH)
    ) inst_interpolator (
        .clk(clk),
        .rst(rst),
        .theta_in(cordic1_to_interp_theta),
        .valid_in(cordic1_to_interp_valid),
        
        // Salidas ya preparadas por el módulo
        .fifo_re(fifo_re),
        .cordic_theta(interp_cordic_theta),
        .cordic_valid(interp_cordic_valid)
    );

    // 2.5. CORDIC 2: Rotación (IP de Vivado)
    // Cable intermedio de 48 bits para la salida AXI del CORDIC 2
    logic [47:0] cordic2_dout_tdata;

    cordic_rot_ip inst_cordic_rot (
        .aclk(clk),
        
        // 1. Fase (Ya viene retrasada y negada del interpolador)
        .s_axis_phase_tvalid(interp_cordic_valid),
        .s_axis_phase_tdata({ {6{interp_cordic_theta[17]}}, interp_cordic_theta }),
        
        // 2. Datos Cartesianos (Conectamos el valid del interpolador, y los datos de la FIFO)
        .s_axis_cartesian_tvalid(interp_cordic_valid),
        // Adaptador de 32 a 48 bits (Extendiendo el signo 8 bits por canal)
        .s_axis_cartesian_tdata({
            {8{fifo_to_cordic2_data[31]}}, fifo_to_cordic2_data[31:16], // 24 bits para Q
            {8{fifo_to_cordic2_data[15]}}, fifo_to_cordic2_data[15:0]   // 24 bits para P
        }),
        
        .m_axis_dout_tvalid(valid_out),
        .m_axis_dout_tdata(cordic2_dout_tdata)
    );


    assign p_out = cordic2_dout_tdata[17:0];
    assign q_out = cordic2_dout_tdata[41:24];

endmodule