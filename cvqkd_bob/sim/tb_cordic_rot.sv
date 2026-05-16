`timescale 1ns / 1ps

module tb_cordic_rot();

    // Señales de reloj y reset
    logic clk;
    logic rst;

    // Entradas al CORDIC
    logic        s_axis_phase_tvalid;
    logic [23:0] s_axis_phase_tdata;
    logic        s_axis_cartesian_tvalid;
    logic [47:0] s_axis_cartesian_tdata;

    // Salidas del CORDIC
    logic        m_axis_dout_tvalid;
    logic [47:0] m_axis_dout_tdata;

    // Valores crudos de entrada (Calculados a partir de los flotantes que me diste)
    // P = 0.0041656494140625 -> Multiplicado por 65536 = 273
    // Q = -0.0040435791015625 -> Multiplicado por 65536 = -265
    // Phase = -1.27926635742188 -> Multiplicado por 32768 (Formato 3Q15) = -41919
    
    logic signed [15:0] raw_P = 16'h0111;
    logic signed [15:0] raw_Q = 16'hfef7;
    logic signed [17:0] raw_phase = 18'hff5c41;

    // Resultados de salida decodificados
    logic signed [15:0] out_P;
    logic signed [15:0] out_Q;
    real out_P_float;
    real out_Q_float;

    // =========================================================================
    // Instancia del IP CORDIC de Rotación
    // =========================================================================
    cordic_rot_ip inst_cordic_rot (
        .aclk(clk),
        
        // Fase de entrada
        .s_axis_phase_tvalid(s_axis_phase_tvalid),
        .s_axis_phase_tdata(s_axis_phase_tdata),
        
        // Coordenadas cartesianas de entrada
        .s_axis_cartesian_tvalid(s_axis_cartesian_tvalid),
        .s_axis_cartesian_tdata(s_axis_cartesian_tdata),
        
        // Salida
        .m_axis_dout_tvalid(m_axis_dout_tvalid),
        .m_axis_dout_tdata(m_axis_dout_tdata)
    );

    // =========================================================================
    // Generación de Reloj
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // Estímulos
    // =========================================================================
    initial begin
        // Inicialización
        rst = 1;
        s_axis_phase_tvalid = 0;
        s_axis_cartesian_tvalid = 0;
        s_axis_phase_tdata = '0;
        s_axis_cartesian_tdata = '0;

        #20;
        rst = 0;
        #10;

        // Inyección de los valores crudos
        @(posedge clk);
        s_axis_phase_tvalid = 1'b1;
        s_axis_cartesian_tvalid = 1'b1;
        
        // Empaquetamos la fase extendiendo el signo a 24 bits
        s_axis_phase_tdata = { {6{raw_phase[17]}}, raw_phase };
        
        // Empaquetamos los datos Cartesianos extendiendo a 24 bits cada uno
        // Q va en los bits altos [47:24], P en los bajos [23:0]
        s_axis_cartesian_tdata = {
            {8{raw_Q[15]}}, raw_Q,
            {8{raw_P[15]}}, raw_P
        };

        // Solo inyectamos durante 1 ciclo
        @(posedge clk);
        s_axis_phase_tvalid = 0;
        s_axis_cartesian_tvalid = 0;

        // Esperamos a que salga el dato (típicamente 20-30 ciclos)
        wait(m_axis_dout_tvalid == 1'b1);
        
        // Extraemos los resultados usando la lógica correcta
        out_P = m_axis_dout_tdata[23:8];   // 16 bits MSB de P (P está en [23:0])
        out_Q = m_axis_dout_tdata[47:32];  // 16 bits MSB de Q (Q está en [47:24])
        // OJO: Xilinx empaca los 24 bits así: P en [23:0], Q en [47:24]
        // Los datos útiles están en los MSBs, así que cogemos [23:8] y [47:32]
        
        // Pasamos a float para imprimir (dividimos por 65536 igual que asumo que hace MATLAB)
        out_P_float = real'(out_P) / 65536.0;
        out_Q_float = real'(out_Q) / 65536.0;

        $display("=================================================");
        $display("RESULTADOS CORDIC DE ROTACION");
        $display("=================================================");
        $display("ENTRADAS:");
        $display("  P_raw     = %0d (Float = %f)", raw_P, real'(raw_P)/65536.0);
        $display("  Q_raw     = %0d (Float = %f)", raw_Q, real'(raw_Q)/65536.0);
        $display("  Phase_raw = %0d (Radianes = %f)", raw_phase, real'(raw_phase)/32768.0);
        $display("-------------------------------------------------");
        $display("SALIDAS DEL HARDWARE:");
        $display("  P_out_raw = %0d (Float = %f)", out_P, out_P_float);
        $display("  Q_out_raw = %0d (Float = %f)", out_Q, out_Q_float);
        $display("=================================================");

        #100;
        $finish;
    end

endmodule
