`timescale 1ns / 1ps

module fsm_estimator #(
    parameter NUM_SAMPLES = 26112
)(
    input  logic        clk,
    input  logic        rst,
    
    input  logic        start,      // Inicio del proceso
    input  logic        ping_pong_bit,  // A o B
    
    output logic        start_math, // Dispara las divisiones finales
    input  logic        math_done,  // Avisa de que T y xi están listos
    
    output logic        done,       // Bandera final para la CPU
    
    output logic [14:0] ptr_addr,
    input  logic [15:0] ptr_data,
    output logic [16:0] bob_addr,
    output logic [14:0] alice_addr,
    
    input  logic [15:0] alice_items_avail,
    input  logic [15:0] bob_items_avail,
    
    output logic        mac_clear,  // Limpia el acumulador
    output logic        mac_enable  // Habilita la suma
);

    // Añadimos el nuevo estado MATH_WAIT
    typedef enum logic [2:0] {
        IDLE,
        RUN,
        DRAIN,
        MATH_WAIT,
        DONE
    } state_t;
    
    state_t state, next_state;

    logic [14:0] counter;
    logic [14:0] count_delay_1;
    logic        active_flag;
    logic        enable_delay_1, enable_delay_2;
    logic [3:0]  drain_counter;

    always_ff @(posedge clk) begin
        if (rst) begin
            state          <= IDLE;
            counter        <= '0;
            count_delay_1  <= '0;
            enable_delay_1 <= 1'b0;
            enable_delay_2 <= 1'b0;
            drain_counter  <= '0;
        end else begin
            state <= next_state;
            
            enable_delay_1 <= active_flag;
            enable_delay_2 <= enable_delay_1;
            count_delay_1  <= counter;

            if (state == IDLE) begin
                counter       <= '0;
                drain_counter <= '0;
            end else if (state == RUN) begin
                // Solo incrementamos si hay datos listos en ambas memorias
                if (counter < alice_items_avail && counter < bob_items_avail) begin
                    if (counter < NUM_SAMPLES - 1) begin
                        counter <= counter + 1'b1;
                    end
                end
            end else if (state == DRAIN) begin
                drain_counter <= drain_counter + 1'b1;
            end
        end
    end

    always_comb begin
        next_state  = state;
        active_flag = 1'b0;
        mac_clear   = 1'b0;
        done        = 1'b0;
        start_math  = 1'b0; // Por defecto a 0

        case (state)
            IDLE: begin
                mac_clear = 1'b1;
                if (start) next_state = RUN;
            end
            
            RUN: begin
                // Solo activamos el pipeline y comprobamos fin de cuenta si hay datos
                if (counter < alice_items_avail && counter < bob_items_avail) begin
                    active_flag = 1'b1;
                    if (counter == NUM_SAMPLES - 1) next_state = DRAIN;
                end
            end
            
            DRAIN: begin
                if (drain_counter == 4'd8) begin
                    start_math = 1'b1; // ¡Disparamos el cálculo final!
                    next_state = MATH_WAIT;
                end
            end
            
            MATH_WAIT: begin
                // La FSM se congela aquí hasta que las divisiones terminen
                if (math_done) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                done = 1'b1; // ¡Todo el proceso ha terminado!
                if (!start) next_state = IDLE;
            end
        endcase
    end

    assign ptr_addr   = counter;
    assign bob_addr   = {ping_pong_bit, ptr_data};
    assign alice_addr = count_delay_1;
    assign mac_enable = enable_delay_2;

endmodule