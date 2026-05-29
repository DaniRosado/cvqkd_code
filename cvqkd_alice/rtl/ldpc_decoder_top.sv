`timescale 1ns / 1ps

module ldpc_decoder_top #(
    parameter int Z = 384,
    parameter int W = 8,
    parameter int BUS_WIDTH = Z * W,
    parameter int PIPELINE_DEPTH = 3 // Ajustado a los 3 registros que pusimos en el Datapath
)(
    input  logic                 clk,
    input  logic                 rst_n,
    
    // --- Interfaz de Control General ---
    input  logic                 start_decoding,
    output logic                 decoding_done,
    output logic                 decoding_success, // 1 = Convergió, 0 = Falló tras Max Iter
    
    // --- Interfaz de Carga (Loader) de LLRs Iniciales ---
    input  logic                 load_mode,        // 1 = Modo carga externa, 0 = Modo decodificación
    input  logic                 load_write_en,
    input  logic [6:0]           load_write_addr,
    input  logic [BUS_WIDTH-1:0] load_write_data
);

    // ==========================================
    // 1. CABLES DE INTERCONEXIÓN (Wires)
    // ==========================================
    
    // Cables FSM <-> Memorias
    logic [6:0] fsm_p_read_addr, fsm_p_write_addr;
    logic [8:0] fsm_r_read_addr, fsm_r_write_addr;
    logic       fsm_p_write_en,  fsm_r_write_en;
    
    // Cables FSM <-> Datapath
    logic       fsm_dp_valid_in;
    logic       fsm_dp_start_row;
    logic [6:0] fsm_dp_col_idx;
    logic [8:0] fsm_dp_shift;
    
    // Cables Memorias <-> Datapath
    logic [BUS_WIDTH-1:0] p_read_data, r_read_data;
    logic [BUS_WIDTH-1:0] dp_p_write_data, dp_r_write_data;
    
    // Cables FSM <-> Syndrome Checker
    logic fsm_iter_start;
    logic fsm_row_done;
    logic is_converged;
    
    // ==========================================
    // 2. MULTIPLEXOR DE CARGA PARA L_BRAM
    // ==========================================
    // Cuando load_mode es 1, el exterior toma el control del puerto de escritura
    logic       mux_p_write_en;
    logic [6:0] mux_p_write_addr;
    logic [BUS_WIDTH-1:0] mux_p_write_data;
    
    always_comb begin
        if (load_mode) begin
            mux_p_write_en   = load_write_en;
            mux_p_write_addr = load_write_addr;
            mux_p_write_data = load_write_data;
        end else begin
            mux_p_write_en   = fsm_p_write_en;
            mux_p_write_addr = fsm_p_write_addr;
            mux_p_write_data = dp_p_write_data;
        end
    end

    // ==========================================
    // 3. INSTANCIACIÓN DE MEMORIAS
    // ==========================================
    
    L_BRAM #(.Z(Z), .W(W)) u_L_BRAM (
        .clk       (clk),
        .read_addr (fsm_p_read_addr),
        .read_data (p_read_data),
        .write_en  (mux_p_write_en),
        .write_addr(mux_p_write_addr),
        .write_data(mux_p_write_data)
    );

    R_BRAM #(.Z(Z), .W(W)) u_R_BRAM (
        .clk       (clk),
        .read_addr (fsm_r_read_addr),
        .read_data (r_read_data),
        .write_en  (fsm_r_write_en),
        .write_addr(fsm_r_write_addr),
        .write_data(dp_r_write_data)
    );

    // Memoria interna (ROM) para el síndrome esperado de Alice
    // Inicializada directamente desde el archivo exportado de MATLAB
    logic [Z-1:0] target_syndrome_mem [0:45];
    initial $readmemb("/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/expected_syndrome.txt", target_syndrome_mem);
    
    logic [5:0] current_row_idx; // Proviene de la FSM

    // ==========================================
    // 4. INSTANCIACIÓN DEL CONTROLADOR (FSM)
    // ==========================================
    
    ldpc_controller_fsm #(.PIPELINE_DEPTH(PIPELINE_DEPTH)) u_FSM (
        .clk              (clk),
        .rst_n            (rst_n),
        .start_decoding   (start_decoding),
        
        // Direcciones de Memoria
        .p_read_addr      (fsm_p_read_addr),
        .r_read_addr      (fsm_r_read_addr),
        .p_write_en       (fsm_p_write_en),
        .p_write_addr     (fsm_p_write_addr),
        .r_write_en       (fsm_r_write_en),
        .r_write_addr     (fsm_r_write_addr),
        
        // Control al Datapath
        .datapath_valid_in(fsm_dp_valid_in),
        .datapath_start_row(fsm_dp_start_row),
        .datapath_col_idx (fsm_dp_col_idx),
        .datapath_shift   (fsm_dp_shift),
        
        // Interfaz de Síndrome
        .current_row_idx  (current_row_idx),
        .iter_start       (fsm_iter_start),
        .row_done         (fsm_row_done),
        .is_converged     (is_converged),
        
        // Salidas Finales
        .decoding_done    (decoding_done),
        .decoding_success (decoding_success)
    );

    // ==========================================
    // 5. INSTANCIACIÓN DEL DATAPATH (Matemática)
    // ==========================================
    
    // Necesitamos extraer los signos totales calculados por la CNU 
    // para enviarlos al Syndrome Checker.
    logic [Z-1:0] cn_total_signs;
    
    ldpc_layer_datapath #(.Z(Z), .W(W)) u_DATAPATH (
        .clk               (clk),
        .rst_n             (rst_n),
        
        // Control
        .valid_in          (fsm_dp_valid_in),
        .start_row         (fsm_dp_start_row),
        .col_idx_in        (fsm_dp_col_idx),
        .shift_val         (fsm_dp_shift),
        
        // Datos de lectura
        .p_read_data_flat  (p_read_data),
        .r_read_data_flat  (r_read_data),
        
        // Datos de escritura (al Multiplexor y a R_BRAM)
        .p_write_data_flat (dp_p_write_data),
        .r_write_data_flat (dp_r_write_data),
        
        // Extracción de signos para el Síndrome (Este puerto hay que añadirlo al Datapath)
        .cn_signs_out      (cn_total_signs),

        // Inyectamos la fila actual del síndrome en las matemáticas
        .target_syn_row    (target_syndrome_mem[current_row_idx])
    );

    // ==========================================
    // 6. INSTANCIACIÓN DEL SYNDROME CHECKER
    // ==========================================
    
    syndrome_checker #(.Z(Z)) u_SYNDROME (
        .clk          (clk),
        .rst_n        (rst_n),
        .iter_start   (fsm_iter_start),
        .row_done     (fsm_row_done),
        .cn_signs     (cn_total_signs),
        .target_syn   (target_syndrome_mem[current_row_idx]), // Síndrome de Alice para esta fila
        .is_converged (is_converged)
    );

endmodule