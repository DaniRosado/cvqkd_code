`timescale 1ns / 1ps

module tb_mdr_8d_rx;

    localparam int N_BLOCKS = 3264;
    localparam int N_SYMBOLS = 13056;
    localparam int ADDR_W = 17;

    logic clk, rst_n;
    logic start;
    logic [ADDR_W-1:0] base_addr;
    logic signed [31:0] m0, m1, m2, m3, m4, m5, m6, m7;
    logic signed [31:0] k_llr;
    logic ready, valid_out;
    logic signed [31:0] llr0, llr1, llr2, llr3, llr4, llr5, llr6, llr7;

    logic [31:0] alice_mem [0:N_SYMBOLS-1];
    logic [31:0] alice_data;
    logic [ADDR_W-1:0] alice_addr;

    logic signed [31:0] ref_m [0:N_BLOCKS*8-1];
    logic signed [31:0] ref_llr [0:N_BLOCKS*8-1];
    logic ref_loaded = 0;

    int errors, total;
    int block_idx;

    mdr_8d_rx #(
        .ADDR_W(ADDR_W),
        .DATA_W(32)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .alice_addr(alice_addr),
        .alice_data(alice_data),
        .start(start),
        .base_addr(base_addr),
        .m0(m0), .m1(m1), .m2(m2), .m3(m3),
        .m4(m4), .m5(m5), .m6(m6), .m7(m7),
        .k_llr(k_llr),
        .ready(ready),
        .valid_out(valid_out),
        .llr0(llr0), .llr1(llr1), .llr2(llr2), .llr3(llr3),
        .llr4(llr4), .llr5(llr5), .llr6(llr6), .llr7(llr7)
    );

    always #5 clk = ~clk;

    always_comb begin
        alice_data = alice_mem[alice_addr];
    end

    initial begin
        int f;
        string line;

        f = $fopen("../cvqkd_matlab/data/alice_key_data.txt", "r");
        if (f == 0) begin
            $display("ERROR: Cannot open alice_key_data.txt");
            $finish;
        end
        for (int i = 0; i < N_SYMBOLS; i++) begin
            if ($fgets(line, f)) begin
                alice_mem[i] = line.atohex();
            end
        end
        $fclose(f);
        $display("Loaded %0d symbols from alice_key_data.txt", N_SYMBOLS);

        f = $fopen("../cvqkd_matlab/data/expected_m_messages.txt", "r");
        if (f == 0) begin
            $display("ERROR: Cannot open expected_m_messages.txt");
            $finish;
        end
        for (int i = 0; i < N_BLOCKS * 8; i++) begin
            if ($fgets(line, f)) begin
                ref_m[i] = $signed({line.atohex()});
            end
        end
        $fclose(f);
        $display("Loaded %0d m messages from expected_m_messages.txt", N_BLOCKS * 8);

        f = $fopen("../cvqkd_matlab/data/expected_llr_lut.txt", "r");
        if (f == 0) begin
            $display("ERROR: Cannot open expected_llr_lut.txt");
            $finish;
        end
        for (int i = 0; i < N_BLOCKS * 8; i++) begin
            if ($fgets(line, f)) begin
                ref_llr[i] = $signed({line.atohex()});
            end
        end
        $fclose(f);
        $display("Loaded %0d expected LLR from expected_llr_lut.txt", N_BLOCKS * 8);

        ref_loaded = 1;
    end

    initial begin
        clk = 0;
        rst_n = 0;
        start = 0;
        base_addr = 0;
        m0 = 0; m1 = 0; m2 = 0; m3 = 0;
        m4 = 0; m5 = 0; m6 = 0; m7 = 0;
        k_llr = 32'h00018E1E;
        errors = 0;
        total = 0;
        block_idx = 0;

        #100;
        rst_n = 1;
        #100;

        wait (ref_loaded);

        for (block_idx = 0; block_idx < N_BLOCKS; block_idx++) begin
            @(posedge clk);
            while (!ready) @(posedge clk);

            m0 = ref_m[block_idx * 8 + 0];
            m1 = ref_m[block_idx * 8 + 1];
            m2 = ref_m[block_idx * 8 + 2];
            m3 = ref_m[block_idx * 8 + 3];
            m4 = ref_m[block_idx * 8 + 4];
            m5 = ref_m[block_idx * 8 + 5];
            m6 = ref_m[block_idx * 8 + 6];
            m7 = ref_m[block_idx * 8 + 7];

            base_addr = block_idx * 4;
            start = 1;
            @(posedge clk);
            start = 0;

            while (!valid_out) @(posedge clk);

            @(negedge clk);
            total++;

            if (llr0 !== ref_llr[block_idx * 8 + 0]) begin
                $display("ERROR block %0d dim 0: got %08X expected %08X",
                    block_idx, llr0, ref_llr[block_idx * 8 + 0]);
                errors++;
            end
            if (llr1 !== ref_llr[block_idx * 8 + 1]) begin
                $display("ERROR block %0d dim 1: got %08X expected %08X",
                    block_idx, llr1, ref_llr[block_idx * 8 + 1]);
                errors++;
            end
            if (llr2 !== ref_llr[block_idx * 8 + 2]) begin
                $display("ERROR block %0d dim 2: got %08X expected %08X",
                    block_idx, llr2, ref_llr[block_idx * 8 + 2]);
                errors++;
            end
            if (llr3 !== ref_llr[block_idx * 8 + 3]) begin
                $display("ERROR block %0d dim 3: got %08X expected %08X",
                    block_idx, llr3, ref_llr[block_idx * 8 + 3]);
                errors++;
            end
            if (llr4 !== ref_llr[block_idx * 8 + 4]) begin
                $display("ERROR block %0d dim 4: got %08X expected %08X",
                    block_idx, llr4, ref_llr[block_idx * 8 + 4]);
                errors++;
            end
            if (llr5 !== ref_llr[block_idx * 8 + 5]) begin
                $display("ERROR block %0d dim 5: got %08X expected %08X",
                    block_idx, llr5, ref_llr[block_idx * 8 + 5]);
                errors++;
            end
            if (llr6 !== ref_llr[block_idx * 8 + 6]) begin
                $display("ERROR block %0d dim 6: got %08X expected %08X",
                    block_idx, llr6, ref_llr[block_idx * 8 + 6]);
                errors++;
            end
            if (llr7 !== ref_llr[block_idx * 8 + 7]) begin
                $display("ERROR block %0d dim 7: got %08X expected %08X",
                    block_idx, llr7, ref_llr[block_idx * 8 + 7]);
                errors++;
            end

            if (block_idx % 100 == 0)
                $display("Block %0d / %0d (%d%%)", block_idx, N_BLOCKS, block_idx*100/N_BLOCKS);
        end

        $display("");
        $display("========================================");
        $display("MDR RX Verification Complete");
        $display("  Blocks processed: %0d", N_BLOCKS);
        $display("  Total comparisons: %0d", total * 8);
        $display("  Errors: %0d", errors);
        if (errors == 0)
            $display("  RESULT: PASS");
        else
            $display("  RESULT: FAIL");
        $display("========================================");
        $finish;
    end

endmodule
