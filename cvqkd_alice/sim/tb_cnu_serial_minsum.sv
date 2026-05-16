`timescale 1ns / 1ps

module tb_cnu_serial_minsum;

    // =========================================================================
    // 1. Parámetros y Señales
    // =========================================================================
    parameter int W = 8;
    parameter int COL_W = 7;

    logic             clk;
    logic             rst_n;
    logic             start_row;
    logic             valid_in;
    logic [COL_W-1:0] col_idx;
    logic [W-1:0]     msg_in;
    
    logic [W-2:0]     min1;
    logic [W-2:0]     min2;
    logic [COL_W-1:0] min1_idx;
    logic             total_sign;

    // =========================================================================
    // 2. Instanciación del Unit Under Test (UUT)
    // =========================================================================
    cnu_serial_minsum #(
        .W(W),
        .COL_W(COL_W)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start_row(start_row),
        .valid_in(valid_in),
        .col_idx(col_idx),
        .msg_in(msg_in),
        .min1(min1),
        .min2(min2),
        .min1_idx(min1_idx),
        .total_sign(total_sign)
    );

    // =========================================================================
    // 3. Generador de Reloj (100 MHz)
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // 4. Tarea auxiliar para inyectar datos fácilmente
    // =========================================================================
    task feed_llr(
        input logic [COL_W-1:0] idx, 
        input logic             signo, 
        input logic [W-2:0]     magnitud
    );
        begin
            @(posedge clk); // Esperamos al flanco de subida
            valid_in <= 1'b1;
            col_idx  <= idx;
            msg_in   <= {signo, magnitud}; // Concatenamos signo y magnitud
        end
    endtask

    // =========================================================================
    // 5. Escenario de Prueba (Estímulos y Verificación)
    // =========================================================================
    initial begin
        $display("=================================================");
        $display(" Iniciando Verificación de CNU (Min-Sum Serie)   ");
        $display("=================================================");

        // Inicialización
        rst_n     = 0;
        start_row = 0;
        valid_in  = 0;
        col_idx   = '0;
        msg_in    = '0;
        
        #25 rst_n = 1; // Liberamos reset

        // --- INICIO DE FILA ---
        @(posedge clk);
        start_row <= 1'b1;
        @(posedge clk);
        start_row <= 1'b0;

        // --- INYECCIÓN DE MENSAJES (Ciclo a ciclo) ---
        $display("[INFO] Inyectando secuencia de mensajes LLR...");
        
        // Formato: feed_llr(columna, signo, magnitud)
        feed_llr(7'd12, 1'b1, 7'd45); // Col 12: Mag = 45, Signo = 1
        feed_llr(7'd24, 1'b0, 7'd18); // Col 24: Mag = 18, Signo = 0  -> (Posible Min2)
        feed_llr(7'd35, 1'b1, 7'd82); // Col 35: Mag = 82, Signo = 1
        feed_llr(7'd42, 1'b1, 7'd5);  // Col 42: Mag = 5,  Signo = 1  -> (Posible Min1)
        feed_llr(7'd60, 1'b0, 7'd12); // Col 60: Mag = 12, Signo = 0  -> (Desplaza a Min2)

        // Detenemos la inyección
        @(posedge clk);
        valid_in <= 1'b0;
        
        // Esperamos un ciclo más para que se asienten los registros de salida
        @(posedge clk);

        // --- VERIFICACIÓN AUTOMÁTICA ---
        $display("-------------------------------------------------");
        $display(" RESULTADOS DEL CÁLCULO DE LA FILA               ");
        $display("-------------------------------------------------");
        
        // Resultados esperados:
        // Min1: 5 (columna 42)
        // Min2: 12 (columna 60, desplazó al 18)
        // Signo Total: 1 ^ 0 ^ 1 ^ 1 ^ 0 = 1
        
        if (min1 !== 7'd5 || min2 !== 7'd12 || min1_idx !== 7'd42 || total_sign !== 1'b1) begin
            $display("[FAIL] El hardware de la CNU ha fallado.");
            $display("       Esperado -> Min1: 5, Min2: 12, Idx: 42, Signo: 1");
            $display("       Obtenido -> Min1: %0d, Min2: %0d, Idx: %0d, Signo: %b", min1, min2, min1_idx, total_sign);
        end else begin
            $display("[SUCCESS] CNU validada correctamente.");
            $display("          Min1 absoluto : %0d (en columna %0d)", min1, min1_idx);
            $display("          Min2 absoluto : %0d", min2);
            $display("          Signo XOR sum : %b", total_sign);
        end
        
        $display("=================================================");
        $finish;
    end

endmodule