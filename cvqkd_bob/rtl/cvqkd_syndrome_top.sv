`timescale 1ns / 1ps

module cvqkd_syndrome_top (
    input  logic         clk,
    input  logic         rst_n,       // Reset asíncrono GLOBAL (Botón de la placa / Power-on)
    input  logic         init_frame,  // SEÑAL SÍNCRONA DE LA FSM: "Limpia y prepárate para nueva trama"
    
    // --- Interfaz de entrada (Desde el MDR) ---
    input  logic         valid_key,   
    input  logic [7:0]   key_in,      
    
    // --- Interfaz de salida ---
    output logic         done,        
    output logic [383:0] syndrome_out [0:45] 
);

    logic [5:0]   bit_cnt;   
    logic [6:0]   word_cnt;  
    logic [383:0] shift_reg; 
    
    logic         bram_we;
    logic [6:0]   bram_addr_w;
    logic [383:0] bram_data_w;
    
    logic         start_calc; 

    // BRAM del Síndrome
    (* ram_style = "block" *) logic [383:0] key_bram [0:67];
    logic [6:0]   u_addr;
    logic [383:0] u_data_in;

    always_ff @(posedge clk) begin
        if (bram_we) key_bram[bram_addr_w] <= bram_data_w;
        u_data_in <= key_bram[u_addr]; 
    end

    // =========================================================================
    // PATRÓN DE DOBLE RESET (Asíncrono duro + Síncrono blando)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 1. Catástrofe / Arranque (Asíncrono)
            bit_cnt     <= '0;
            word_cnt    <= '0;
            shift_reg   <= '0;
            bram_we     <= 1'b0;
            start_calc  <= 1'b0;
            bram_addr_w <= '0;
            bram_data_w <= '0;
            
        end else if (init_frame) begin
            // 2. Orden de la FSM de empezar nueva trama (Síncrono al reloj)
            bit_cnt     <= '0;
            word_cnt    <= '0;
            shift_reg   <= '0;
            bram_we     <= 1'b0;
            start_calc  <= 1'b0;
            bram_addr_w <= '0;
            
        end else begin
            // 3. Operación normal
            bram_we    <= 1'b0;
            start_calc <= 1'b0;
            
            if (valid_key) begin
                shift_reg <= {key_in, shift_reg[383:8]};
                
                if (bit_cnt == 6'd47) begin
                    bit_cnt     <= '0;
                    bram_we     <= 1'b1;
                    bram_addr_w <= word_cnt;
                    bram_data_w <= {key_in, shift_reg[383:8]}; 
                    
                    if (word_cnt == 7'd67) begin
                        word_cnt   <= '0;
                        start_calc <= 1'b1; 
                    end else begin
                        word_cnt <= word_cnt + 1;
                    end
                end else begin
                    bit_cnt <= bit_cnt + 1;
                end
            end
        end
    end

    // Instancia del núcleo matemático
    syndrome_calc_bg1 sync_calc_inst (
        .clk(clk),
        .rst_n(rst_n),           // El reset global asíncrono
        .init_frame(init_frame), // <--- ¡OJO AQUÍ! Pasamos la señal de limpieza hacia abajo
        .start(start_calc),      
        .u_addr(u_addr),         
        .u_data_in(u_data_in),   
        .done(done),
        .syndrome_out(syndrome_out)
    );

endmodule