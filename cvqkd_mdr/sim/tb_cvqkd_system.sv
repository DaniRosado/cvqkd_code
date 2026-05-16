`timescale 1ns / 1ps

module tb_cvqkd_system;

    localparam int N_BLOCKS  = 3264;
    localparam int N_SYMBOLS = 13056;
    localparam int ADDR_W = 17;

    logic clk, rst_n;

    // TX
    logic        tx_start, tx_ready, tx_valid_out;
    logic [ADDR_W-1:0] tx_addr;
    logic [31:0] tx_data;
    logic [7:0]  random_bits;
    logic signed [31:0] tx_m0, tx_m1, tx_m2, tx_m3,
                         tx_m4, tx_m5, tx_m6, tx_m7;

    // RX
    logic        rx_start, rx_ready, rx_valid_out;
    logic [ADDR_W-1:0] rx_addr;
    logic [31:0] rx_data;
    logic signed [31:0] rx_m0, rx_m1, rx_m2, rx_m3,
                         rx_m4, rx_m5, rx_m6, rx_m7;
    logic signed [31:0] llr0, llr1, llr2, llr3,
                         llr4, llr5, llr6, llr7;
    logic signed [31:0] k_llr;

    // BRAMs
    logic [31:0] bob_mem   [0:N_SYMBOLS-1];
    logic [31:0] alice_mem [0:N_SYMBOLS-1];

    // Reference
    logic [7:0]  ref_bits [0:N_BLOCKS*8-1];
    logic signed [31:0] ref_m   [0:N_BLOCKS*8-1];
    logic signed [31:0] ref_llr [0:N_BLOCKS*8-1];

    int err_m, err_llr, block_idx;

    // ── Instances ──
    logic [ADDR_W-1:0] blk_addr;

    mdr_8d_tx #(.ADDR_W(ADDR_W), .DATA_W(32)) tx (
        .clk(clk), .rst_n(rst_n),
        .bram_addr(tx_addr), .bram_data(tx_data),
        .start(tx_start), .base_addr(blk_addr),
        .random_bits(random_bits),
        .ready(tx_ready), .valid_out(tx_valid_out),
        .m0(tx_m0), .m1(tx_m1), .m2(tx_m2), .m3(tx_m3),
        .m4(tx_m4), .m5(tx_m5), .m6(tx_m6), .m7(tx_m7)
    );

    mdr_8d_rx #(.ADDR_W(ADDR_W), .DATA_W(32)) rx (
        .clk(clk), .rst_n(rst_n),
        .alice_addr(rx_addr), .alice_data(rx_data),
        .start(rx_start), .base_addr(blk_addr),
        .m0(rx_m0), .m1(rx_m1), .m2(rx_m2), .m3(rx_m3),
        .m4(rx_m4), .m5(rx_m5), .m6(rx_m6), .m7(rx_m7),
        .k_llr(k_llr),
        .ready(rx_ready), .valid_out(rx_valid_out),
        .llr0(llr0), .llr1(llr1), .llr2(llr2), .llr3(llr3),
        .llr4(llr4), .llr5(llr5), .llr6(llr6), .llr7(llr7)
    );

    assign tx_data   = bob_mem[tx_addr];
    assign rx_data   = alice_mem[rx_addr];

    always #5 clk = ~clk;

    // ── Load data ──
    initial begin
        string line; int f;

        f = $fopen("../cvqkd_matlab/data/bob_key_ram.txt", "r");
        for (int i = 0; i < N_SYMBOLS; i++) begin
            $fgets(line, f); bob_mem[i] = line.atohex();
        end
        $fclose(f);

        f = $fopen("../cvqkd_matlab/data/alice_key_data.txt", "r");
        for (int i = 0; i < N_SYMBOLS; i++) begin
            $fgets(line, f); alice_mem[i] = line.atohex();
        end
        $fclose(f);

        f = $fopen("../cvqkd_matlab/data/bob_random_bits.txt", "r");
        for (int i = 0; i < N_BLOCKS*8; i++) begin
            $fgets(line, f); ref_bits[i] = (line.atoi() != 0);
        end
        $fclose(f);

        f = $fopen("../cvqkd_matlab/data/expected_m_messages.txt", "r");
        for (int i = 0; i < N_BLOCKS*8; i++) begin
            $fgets(line, f); ref_m[i] = $signed({line.atohex()});
        end
        $fclose(f);

        f = $fopen("../cvqkd_matlab/data/expected_llr_lut.txt", "r");
        for (int i = 0; i < N_BLOCKS*8; i++) begin
            $fgets(line, f); ref_llr[i] = $signed({line.atohex()});
        end
        $fclose(f);

        $display("Loaded all reference data (%0d blocks, %0d symbols).",
                 N_BLOCKS, N_SYMBOLS);
    end

    // ── Pipeline: TX then RX per block ──
    initial begin
        clk = 0; rst_n = 0;
        tx_start = 0; rx_start = 0;
        k_llr = 32'h00018E1E;
        {rx_m0, rx_m1, rx_m2, rx_m3, rx_m4, rx_m5, rx_m6, rx_m7} = 0;
        err_m = 0; err_llr = 0;

        #100; rst_n = 1; #100;

        for (block_idx = 0; block_idx < N_BLOCKS; block_idx++) begin
            @(posedge clk);
            while (!tx_ready || !rx_ready) @(posedge clk);

            blk_addr = block_idx * 4;

            // ── Start TX (same timing as tb_mdr_8d_tx) ──
            random_bits[0] = ref_bits[block_idx*8+0];
            random_bits[1] = ref_bits[block_idx*8+1];
            random_bits[2] = ref_bits[block_idx*8+2];
            random_bits[3] = ref_bits[block_idx*8+3];
            random_bits[4] = ref_bits[block_idx*8+4];
            random_bits[5] = ref_bits[block_idx*8+5];
            random_bits[6] = ref_bits[block_idx*8+6];
            random_bits[7] = ref_bits[block_idx*8+7];
            tx_start = 1;
            @(posedge clk);
            tx_start = 0;

            // Wait for TX m output
            while (!tx_valid_out) @(posedge clk);
            @(negedge clk);
            {rx_m0, rx_m1, rx_m2, rx_m3, rx_m4, rx_m5, rx_m6, rx_m7} =
                {tx_m0, tx_m1, tx_m2, tx_m3, tx_m4, tx_m5, tx_m6, tx_m7};

            // Compare TX output m vs reference
            if (tx_m0 !== ref_m[block_idx*8+0]) begin
                $display("ERROR m block %0d dim 0: got %08X expected %08X",
                    block_idx, tx_m0, ref_m[block_idx*8+0]); err_m++;
            end
            if (tx_m1 !== ref_m[block_idx*8+1]) begin
                $display("ERROR m block %0d dim 1: got %08X expected %08X",
                    block_idx, tx_m1, ref_m[block_idx*8+1]); err_m++;
            end
            if (tx_m2 !== ref_m[block_idx*8+2]) begin
                $display("ERROR m block %0d dim 2: got %08X expected %08X",
                    block_idx, tx_m2, ref_m[block_idx*8+2]); err_m++;
            end
            if (tx_m3 !== ref_m[block_idx*8+3]) begin
                $display("ERROR m block %0d dim 3: got %08X expected %08X",
                    block_idx, tx_m3, ref_m[block_idx*8+3]); err_m++;
            end
            if (tx_m4 !== ref_m[block_idx*8+4]) begin
                $display("ERROR m block %0d dim 4: got %08X expected %08X",
                    block_idx, tx_m4, ref_m[block_idx*8+4]); err_m++;
            end
            if (tx_m5 !== ref_m[block_idx*8+5]) begin
                $display("ERROR m block %0d dim 5: got %08X expected %08X",
                    block_idx, tx_m5, ref_m[block_idx*8+5]); err_m++;
            end
            if (tx_m6 !== ref_m[block_idx*8+6]) begin
                $display("ERROR m block %0d dim 6: got %08X expected %08X",
                    block_idx, tx_m6, ref_m[block_idx*8+6]); err_m++;
            end
            if (tx_m7 !== ref_m[block_idx*8+7]) begin
                $display("ERROR m block %0d dim 7: got %08X expected %08X",
                    block_idx, tx_m7, ref_m[block_idx*8+7]); err_m++;
            end

            // ── Start RX (same timing as tb_mdr_8d_rx) ──
            @(posedge clk);
            while (!rx_ready) @(posedge clk);

            rx_start = 1;
            @(posedge clk);
            rx_start = 0;

            while (!rx_valid_out) @(posedge clk);
            @(negedge clk);

            // Compare LLRs
            if (llr0 !== ref_llr[block_idx*8+0]) begin
                $display("ERROR LLR block %0d dim 0: got %08X expected %08X",
                    block_idx, llr0, ref_llr[block_idx*8+0]); err_llr++;
            end
            if (llr1 !== ref_llr[block_idx*8+1]) begin
                $display("ERROR LLR block %0d dim 1: got %08X expected %08X",
                    block_idx, llr1, ref_llr[block_idx*8+1]); err_llr++;
            end
            if (llr2 !== ref_llr[block_idx*8+2]) begin
                $display("ERROR LLR block %0d dim 2: got %08X expected %08X",
                    block_idx, llr2, ref_llr[block_idx*8+2]); err_llr++;
            end
            if (llr3 !== ref_llr[block_idx*8+3]) begin
                $display("ERROR LLR block %0d dim 3: got %08X expected %08X",
                    block_idx, llr3, ref_llr[block_idx*8+3]); err_llr++;
            end
            if (llr4 !== ref_llr[block_idx*8+4]) begin
                $display("ERROR LLR block %0d dim 4: got %08X expected %08X",
                    block_idx, llr4, ref_llr[block_idx*8+4]); err_llr++;
            end
            if (llr5 !== ref_llr[block_idx*8+5]) begin
                $display("ERROR LLR block %0d dim 5: got %08X expected %08X",
                    block_idx, llr5, ref_llr[block_idx*8+5]); err_llr++;
            end
            if (llr6 !== ref_llr[block_idx*8+6]) begin
                $display("ERROR LLR block %0d dim 6: got %08X expected %08X",
                    block_idx, llr6, ref_llr[block_idx*8+6]); err_llr++;
            end
            if (llr7 !== ref_llr[block_idx*8+7]) begin
                $display("ERROR LLR block %0d dim 7: got %08X expected %08X",
                    block_idx, llr7, ref_llr[block_idx*8+7]); err_llr++;
            end

            if (block_idx % 100 == 0)
                $display("Block %0d / %0d (%0d%%)  m_err=%0d llr_err=%0d",
                    block_idx, N_BLOCKS, block_idx*100/N_BLOCKS,
                    err_m, err_llr);
        end

        $display("");
        $display("========================================");
        $display("CV-QKD System Verification Complete");
        $display("  Blocks: %0d", N_BLOCKS);
        $display("  M errors:  %0d / %0d", err_m, N_BLOCKS*8);
        $display("  LLR errors: %0d / %0d", err_llr, N_BLOCKS*8);
        if (err_m == 0 && err_llr == 0)
            $display("  RESULT: PASS");
        else
            $display("  RESULT: FAIL");
        $display("========================================");
        $finish;
    end

endmodule