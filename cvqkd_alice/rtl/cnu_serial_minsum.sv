`timescale 1ns / 1ps

module cnu_serial_minsum #(
    parameter int W = 8,       // Ancho del LLR (1 bit signo + 7 bits magnitud)
    parameter int COL_W = 7    // Ancho del índice de columna (68 columnas -> 7 bits)
)(
    input  logic             clk,
    input  logic             rst_n,
    
    // Señales de Control desde la FSM principal
    input  logic             start_row, // Pulso: limpia registros al iniciar una nueva fila
    input  logic             valid_in,  // Alto cuando el elemento de la matriz H != -1
    
    // Datos de entrada
    input  logic [COL_W-1:0] col_idx,   // Índice de la VNU (columna) actual
    input  logic [W-1:0]     msg_in,    // LLR entrante: {signo, magnitud}

    // Datos de salida (Estado acumulado de la fila)
    output logic [W-2:0]     min1,      // Primer mínimo (M1)
    output logic [W-2:0]     min2,      // Segundo mínimo (M2)
    output logic [COL_W-1:0] min1_idx,  // Índice de la columna que generó M1
    output logic             total_sign // Signo total acumulado (S_total)
);

    // =========================================================================
    // 1. Separación de Signo y Magnitud del LLR entrante
    // =========================================================================
    logic         sign_in;
    logic [W-2:0] mag_in;
    
    // El bit más significativo (MSB) es el signo, el resto es magnitud
    assign sign_in = msg_in[W-1];
    assign mag_in  = msg_in[W-2:0];

    // Constante para inicializar los mínimos al valor máximo posible (todo '1's)
    localparam logic [W-2:0] MAX_MAG = '1;

    // =========================================================================
    // 2. Registros de Estado de la CNU
    // =========================================================================
    logic [W-2:0]     reg_min1;
    logic [W-2:0]     reg_min2;
    logic [COL_W-1:0] reg_min1_idx;
    logic             reg_total_sign;

    // Asignación de registros a las salidas
    assign min1       = reg_min1;
    assign min2       = reg_min2;
    assign min1_idx   = reg_min1_idx;
    assign total_sign = reg_total_sign;

    // =========================================================================
    // 3. Lógica Secuencial (Actualización de Mínimos y Signo)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_min1       <= MAX_MAG;
            reg_min2       <= MAX_MAG;
            reg_min1_idx   <= '0;
            reg_total_sign <= 1'b0;
        end else begin
            if (start_row) begin
                // Reset de las variables al empezar a procesar una nueva fila
                reg_min1       <= MAX_MAG;
                reg_min2       <= MAX_MAG;
                reg_min1_idx   <= '0;
                reg_total_sign <= 1'b0;
            end 
            else if (valid_in) begin
                // 1. Acumulación del signo total (XOR)
                reg_total_sign <= reg_total_sign ^ sign_in;
                
                // 2. Árbol de decisión para actualizar M1 y M2
                if (mag_in < reg_min1) begin
                    // Nuevo mínimo absoluto encontrado
                    // El antiguo M1 pasa a ser M2
                    reg_min2     <= reg_min1;
                    // Actualizamos M1 con el nuevo valor
                    reg_min1     <= mag_in;
                    reg_min1_idx <= col_idx;
                end 
                else if (mag_in < reg_min2) begin
                    // El valor está entre M1 y M2
                    // Solo actualizamos M2
                    reg_min2 <= mag_in;
                end
            end
        end
    end

endmodule