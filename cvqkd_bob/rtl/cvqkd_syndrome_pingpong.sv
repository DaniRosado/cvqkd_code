`timescale 1ns / 1ps

module cvqkd_syndrome_pingpong (
    input  logic         clk,
    input  logic         rst_n,
    
    // --- Interfaz de Entrada (Streaming en paralelo al MDR) ---
    input  logic         valid_data,
    input  logic [7:0]   trng_data,
    
    // --- Interfaz de Salida ---
    output logic         done,
    output logic [383:0] syndrome_out [0:45]
);

    // =========================================================================
    // 1. REGISTROS DE EMPAQUETADO Y CONTROL DE BANCOS
    // =========================================================================
    logic [5:0]   bit_cnt;   
    logic [6:0]   word_cnt;  
    logic [383:0] shift_reg; 
    
    // Punteros del Ping-Pong
    logic         wr_bank;       // 0 = Escribiendo en BRAM 0, 1 = Escribiendo en BRAM 1
    logic         rd_bank;       // 0 = Calculando de BRAM 0,  1 = Calculando de BRAM 1
    
    // Banderas de estado
    logic         bank_0_ready;  // 1 = BRAM 0 llena y lista para calcular
    logic         bank_1_ready;  // 1 = BRAM 1 llena y lista para calcular
    logic         calc_busy;     // 1 = El calculador de síndrome está trabajando

    // Señales internas de escritura/lectura
    logic         bram_we_0, bram_we_1;
    logic [6:0]   u_addr;
    logic [383:0] u_data_in_0, u_data_in_1, u_data_in;
    logic         start_calc;
    logic         calc_done;

    // Conectamos el done interno del calculador al puerto externo
    assign done = calc_done;

    // =========================================================================
    // 2. LAS DOS BRAMS (Ping y Pong)
    // =========================================================================
    (* ram_style = "block" *) logic [383:0] key_bram_0 [0:67];
    (* ram_style = "block" *) logic [383:0] key_bram_1 [0:67];

    always_ff @(posedge clk) begin
        if (bram_we_0) key_bram_0[word_cnt] <= {trng_data, shift_reg[383:8]};
        if (bram_we_1) key_bram_1[word_cnt] <= {trng_data, shift_reg[383:8]};
        
        u_data_in_0 <= key_bram_0[u_addr];
        u_data_in_1 <= key_bram_1[u_addr]; 
    end

    assign u_data_in = (rd_bank == 1'b0) ? u_data_in_0 : u_data_in_1;

    // =========================================================================
    // 3. FSM 1: ESCRITURA Y EMPAQUETADO (Llenado de Bancos)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt      <= '0;
            word_cnt     <= '0;
            shift_reg    <= '0;
            wr_bank      <= 1'b0;
            bank_0_ready <= 1'b0;
            bank_1_ready <= 1'b0;
        end else begin
            if (valid_data) begin
                shift_reg <= {trng_data, shift_reg[383:8]};
                
                if (bit_cnt == 6'd47) begin
                    bit_cnt <= '0;
                    
                    if (word_cnt == 7'd67) begin
                        word_cnt <= '0;
                        if (wr_bank == 1'b0) bank_0_ready <= 1'b1;
                        else                 bank_1_ready <= 1'b1;
                        
                        wr_bank <= ~wr_bank; 
                    end else begin
                        word_cnt <= word_cnt + 1;
                    end
                end else begin
                    bit_cnt <= bit_cnt + 1;
                end
            end
            
            // Consumimos las banderas cuando el calculador las acepta
            if (start_calc) begin
                if (rd_bank == 1'b0) bank_0_ready <= 1'b0;
                else                 bank_1_ready <= 1'b0;
            end
        end
    end

    assign bram_we_0 = valid_data && (bit_cnt == 6'd47) && (wr_bank == 1'b0);
    assign bram_we_1 = valid_data && (bit_cnt == 6'd47) && (wr_bank == 1'b1);

    // =========================================================================
    // 4. FSM 2: LECTURA Y DISPARO (Consumo de Bancos)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_bank    <= 1'b0;
            calc_busy  <= 1'b0;
            start_calc <= 1'b0;
        end else begin
            start_calc <= 1'b0; // Es un pulso de un solo ciclo
            
            if (!calc_busy) begin
                if ((rd_bank == 1'b0 && bank_0_ready) || (rd_bank == 1'b1 && bank_1_ready)) begin
                    start_calc <= 1'b1;
                    calc_busy  <= 1'b1;
                end
            end else begin
                if (calc_done) begin
                    calc_busy <= 1'b0;
                    rd_bank   <= ~rd_bank;
                end
            end
        end
    end

    // =========================================================================
    // 5. INSTANCIACIÓN DEL NÚCLEO MATEMÁTICO
    // =========================================================================
    syndrome_calc_bg1 sync_calc_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_calc),      
        .u_addr(u_addr),         
        .u_data_in(u_data_in),   
        .done(calc_done),
        .syndrome_out(syndrome_out)
    );

endmodule