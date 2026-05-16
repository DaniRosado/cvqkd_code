module generador_direcciones_sacrificio #(
    parameter N_TOTAL_DATOS = 52224
)(
    input  logic        clk,
    input  logic        rst,
    
    // --- Interfaz Serie desde el PC/Microcontrolador ---
    input  logic        mask_valid, // "Data Ready": a 1 cuando entra un bit nuevo
    input  logic        mask_bit,   // El bit (1 = Sacrificar, 0 = Guardar para clave)
    
    // --- Interfaz hacia la RAM de Bob y el Estimador ---
    output logic [15:0] ram_addr,   // Dirección que vamos a leer
    output logic        read_en,    // Señal para decirle a la RAM que lea
    output logic        done        // Termina el proceso
);

    logic [15:0] contador_dir;

    always_ff @(posedge clk) begin
        if (rst) begin
            contador_dir <= '0;
            ram_addr     <= '0;
            read_en      <= 1'b0;
            done         <= 1'b0;
        end else begin
            // Por defecto, no leemos
            read_en <= 1'b0; 
            
            if (mask_valid && !done) begin
                
                if (mask_bit == 1'b1) begin
                    // ¡Toca sacrificar este dato! Lo mandamos a leer.
                    ram_addr <= contador_dir;
                    read_en  <= 1'b1;
                end
                
                // Avanzamos el puntero a la siguiente dirección de la RAM
                if (contador_dir == N_TOTAL_DATOS - 1) begin
                    done <= 1'b1; // Ya hemos recorrido toda la RAM
                end else begin
                    contador_dir <= contador_dir + 1'b1;
                end
            end
        end
    end
endmodule