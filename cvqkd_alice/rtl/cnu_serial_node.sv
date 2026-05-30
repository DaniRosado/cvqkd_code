`timescale 1ns / 1ps

module cnu_serial_node (
    input  logic       clk,
    input  logic       rst_n,
    
    // --- Señales de Control ---
    input  logic       start_row,    // Pulso que indica el inicio de una nueva fila (resetea los mínimos)
    input  logic       valid_in,     // Alto cuando L_q_in y col_idx_in son válidos
    input  logic [6:0] col_idx_in,   // Índice de la columna actual (para saber de quién es el min1)
    
    // --- Entrada de Datos (Desde el Barrel Shifter Directo) ---
    input  logic [7:0] L_q_in,       // Formato Signo-Magnitud
    
    // --- Salida de Datos (Estado Final de la Fila) ---
    output logic [6:0] min1_out,     // Magnitud escalada del primer mínimo
    output logic [6:0] min2_out,     // Magnitud escalada del segundo mínimo
    output logic [6:0] min1_col_out, // Columna dueña del primer mínimo
    output logic       total_sign_out// XOR de todos los signos de la fila
);

    // Registros internos para mantener el estado durante la fila
    logic [6:0] reg_min1, reg_min2;
    logic [6:0] reg_min1_col;
    logic       reg_total_sign;

    // Desglose de la entrada
    logic       in_sign;
    logic [6:0] in_mag;
    assign in_sign = L_q_in[7];
    assign in_mag  = L_q_in[6:0];

    // ==========================================
    // Lógica Secuencial: Búsqueda de Mínimos
    // ==========================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_min1       <= 7'd127; // Infinito (máximo valor en 7 bits)
            reg_min2       <= 7'd127;
            reg_min1_col   <= 7'd0;
            reg_total_sign <= 1'b0;
        end else if (start_row) begin
            // Reseteamos el estado para empezar una fila limpia
            // Si valid_in también es alto en este ciclo, capturamos el primer dato
            if (valid_in) begin
                reg_min1       <= in_mag;
                reg_min2       <= 7'd127;
                reg_min1_col   <= col_idx_in;
                reg_total_sign <= in_sign;
            end else begin
                reg_min1       <= 7'd127;
                reg_min2       <= 7'd127;
                reg_total_sign <= 1'b0;
            end
        end else if (valid_in) begin
            // Acumulamos el signo (XOR)
            reg_total_sign <= reg_total_sign ^ in_sign;

            // Lógica de comparación de mínimos
            if (in_mag < reg_min1) begin
                // El nuevo es el más pequeño absoluto. Desplazamos el podio.
                reg_min2     <= reg_min1;
                reg_min1     <= in_mag;
                reg_min1_col <= col_idx_in;
            // end else if (in_mag < reg_min2 && in_mag > reg_min1) begin
            end else if (in_mag < reg_min2) begin
                // El nuevo bate al segundo, pero no al primero.
                reg_min2     <= in_mag;
            end
        end
    end

    // ==========================================
    // Lógica Combinacional: Scaled Min-Sum (x 0.75)
    // ==========================================
    // Multiplicar por 0.75 es lo mismo que: Valor - (Valor / 4)
    // En binario, dividir por 4 es hacer un shift a la derecha de 2 bits (>> 2).
    
    logic [6:0] scaled_min1, scaled_min2;
    
    always_comb begin
        scaled_min1 = reg_min1 - (reg_min1 >> 2);
        //scaled_min1 = reg_min1;
        scaled_min2 = reg_min2 - (reg_min2 >> 2);
        //scaled_min2 = reg_min2;
    end

    // Asignación a las salidas
    assign min1_out       = scaled_min1;
    assign min2_out       = scaled_min2;
    assign min1_col_out   = reg_min1_col;
    assign total_sign_out = reg_total_sign;

endmodule