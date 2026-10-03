`timescale 1ns / 1ps

// Test aleatorio autocomprobado de sync_fifo: escrituras y lecturas al azar
// (incluidas simultáneas) contra una cola de referencia. Comprueba el orden de
// los datos, la latencia de lectura de 1 ciclo y las banderas full/empty.
module tb_sync_fifo();

    localparam DATA_WIDTH = 32;
    localparam DEPTH      = 8;   // Pequeña para llegar a menudo a llena y vacía
    localparam N_CYCLES   = 5000;

    logic clk = 0;
    logic rst, we, re, empty, full;
    logic [DATA_WIDTH-1:0] din, dout;

    sync_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) dut (
        .clk(clk), .rst(rst), .we(we), .din(din), .re(re),
        .dout(dout), .empty(empty), .full(full)
    );

    always #5 clk = ~clk;

    logic [DATA_WIDTH-1:0] model [$];
    logic [DATA_WIDTH-1:0] expected;
    logic                  check_next = 0;
    int errors = 0, reads = 0, n_full = 0, n_empty = 0;

    initial begin
        rst = 1; we = 0; re = 0; din = '0;
        repeat (3) @(posedge clk);
        #1 rst = 0;

        for (int c = 0; c < N_CYCLES; c++) begin
            @(posedge clk); #1;  // El DUT ya ha procesado los estímulos del ciclo anterior
            // El dato leído en el ciclo anterior ya está en dout
            if (check_next && dout !== expected) begin
                if (errors < 10) $display("  [FAIL] dout = %08h, esperado %08h", dout, expected);
                errors++;
            end
            // Banderas frente al modelo
            if (empty !== (model.size() == 0) || full !== (model.size() == DEPTH)) begin
                if (errors < 10) $display("  [FAIL] banderas: empty=%b full=%b ocupacion=%0d", empty, full, model.size());
                errors++;
            end
            n_full  += full;
            n_empty += empty;

            // Nuevos estímulos (el DUT los registra en el siguiente flanco)
            we  = ($urandom % 3) != 0;
            re  = ($urandom % 3) != 0;
            din = $urandom;
            check_next = re && !empty;
            if (check_next) begin expected = model.pop_front(); reads++; end
            if (we && !full) model.push_back(din);
        end

        $display("tb_sync_fifo: %0d lecturas comprobadas, %0d ciclos llena, %0d ciclos vacia, %0d errores",
                 reads, n_full, n_empty, errors);
        if (errors == 0 && n_full > 0 && n_empty > 0) $display("RESULTADO: PASS");
        else                                          $display("RESULTADO: FAIL");
        $finish;
    end

endmodule
