`timescale 1ns / 1ps

module tb_mdr_8d_tx;

    localparam int N_BLOCKS = 3264;
    localparam int N_SYMBOLS = 13056;
    localparam int ADDR_W = 17;

    logic clk, rst_n;
    logic start;
    logic [ADDR_W-1:0] base_addr;
    logic [7:0] random_bits;
    logic ready, valid_out;
    logic signed [31:0] m0, m1, m2, m3, m4, m5, m6, m7;

    // Simulation memory for bob_key_ram
    logic [31:0] mem [0:N_SYMBOLS-1];
    logic [31:0] bram_data;
    logic [ADDR_W-1:0] bram_addr;

    // Reference data
    logic [7:0] ref_bits [0:N_BLOCKS*8-1];
    logic signed [31:0] ref_m [0:N_BLOCKS*8-1];
    logic ref_loaded = 0;

    // Error counting
    int errors, total;
    int block_idx;

    // DUT
    mdr_8d_tx #(
        .ADDR_W(ADDR_W),
        .DATA_W(32)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .bram_addr(bram_addr),
        .bram_data(bram_data),
        .start(start),
        .base_addr(base_addr),
        .random_bits(random_bits),
        .ready(ready),
        .valid_out(valid_out),
        .m0(m0), .m1(m1), .m2(m2), .m3(m3),
        .m4(m4), .m5(m5), .m6(m6), .m7(m7)
    );

    // Clocks
    always #5 clk = ~clk;

    // Combinational BRAM for simulation (avoids NBA race with addr update)
    always_comb begin
        bram_data = mem[bram_addr];
    end

    // Load reference files
    initial begin
        int f;
        string line;

        // Load bob_key_ram.txt
        f = $fopen("../cvqkd_matlab/data/bob_key_ram.txt", "r");
        if (f == 0) begin
            $display("ERROR: Cannot open bob_key_ram.txt");
            $finish;
        end
        for (int i = 0; i < N_SYMBOLS; i++) begin
            if ($fgets(line, f)) begin
                mem[i] = line.atohex();
            end
        end
        $fclose(f);
        $display("Loaded %0d symbols from bob_key_ram.txt", N_SYMBOLS);

        // Load bob_random_bits.txt
        f = $fopen("../cvqkd_matlab/data/bob_random_bits.txt", "r");
        if (f == 0) begin
            $display("ERROR: Cannot open bob_random_bits.txt");
            $finish;
        end
        for (int i = 0; i < N_BLOCKS * 8; i++) begin
            if ($fgets(line, f)) begin
                ref_bits[i] = (line.atoi() != 0);
            end
        end
        $fclose(f);
        $display("Loaded %0d random bits from bob_random_bits.txt", N_BLOCKS * 8);

        // Load expected_m_messages.txt
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
        $display("Loaded %0d expected m messages from expected_m_messages.txt", N_BLOCKS * 8);

        ref_loaded = 1;
    end

    // Stimulus
    initial begin
        clk = 0;
        rst_n = 0;
        start = 0;
        base_addr = 0;
        random_bits = 0;
        errors = 0;
        total = 0;
        block_idx = 0;

        // Reset
        #100;
        rst_n = 1;
        #100;

        wait (ref_loaded);

        // Process all blocks
        for (block_idx = 0; block_idx < N_BLOCKS; block_idx++) begin
            // Wait for ready (always true at start)
            @(posedge clk);
            while (!ready) @(posedge clk);

            // Set random bits for this block
            random_bits[0] = ref_bits[block_idx * 8 + 0];
            random_bits[1] = ref_bits[block_idx * 8 + 1];
            random_bits[2] = ref_bits[block_idx * 8 + 2];
            random_bits[3] = ref_bits[block_idx * 8 + 3];
            random_bits[4] = ref_bits[block_idx * 8 + 4];
            random_bits[5] = ref_bits[block_idx * 8 + 5];
            random_bits[6] = ref_bits[block_idx * 8 + 6];
            random_bits[7] = ref_bits[block_idx * 8 + 7];

            // Set base address (sequential: 4 symbols per block)
            base_addr = block_idx * 4;
            start = 1;
            @(posedge clk);
            start = 0;

            // Wait for valid_out
            while (!valid_out) @(posedge clk);

            // Sample outputs
            @(negedge clk);
            total++;

            // Compare
            if (m0 !== ref_m[block_idx * 8 + 0]) begin
                $display("ERROR block %0d dim 0: got %08X expected %08X",
                    block_idx, m0, ref_m[block_idx * 8 + 0]);
                errors++;
            end
            if (m1 !== ref_m[block_idx * 8 + 1]) begin
                $display("ERROR block %0d dim 1: got %08X expected %08X",
                    block_idx, m1, ref_m[block_idx * 8 + 1]);
                errors++;
            end
            if (m2 !== ref_m[block_idx * 8 + 2]) begin
                $display("ERROR block %0d dim 2: got %08X expected %08X",
                    block_idx, m2, ref_m[block_idx * 8 + 2]);
                errors++;
            end
            if (m3 !== ref_m[block_idx * 8 + 3]) begin
                $display("ERROR block %0d dim 3: got %08X expected %08X",
                    block_idx, m3, ref_m[block_idx * 8 + 3]);
                errors++;
            end
            if (m4 !== ref_m[block_idx * 8 + 4]) begin
                $display("ERROR block %0d dim 4: got %08X expected %08X",
                    block_idx, m4, ref_m[block_idx * 8 + 4]);
                errors++;
            end
            if (m5 !== ref_m[block_idx * 8 + 5]) begin
                $display("ERROR block %0d dim 5: got %08X expected %08X",
                    block_idx, m5, ref_m[block_idx * 8 + 5]);
                errors++;
            end
            if (m6 !== ref_m[block_idx * 8 + 6]) begin
                $display("ERROR block %0d dim 6: got %08X expected %08X",
                    block_idx, m6, ref_m[block_idx * 8 + 6]);
                errors++;
            end
            if (m7 !== ref_m[block_idx * 8 + 7]) begin
                $display("ERROR block %0d dim 7: got %08X expected %08X",
                    block_idx, m7, ref_m[block_idx * 8 + 7]);
                errors++;
            end

            if (block_idx % 100 == 0)
                $display("Block %0d / %0d (%d%%)", block_idx, N_BLOCKS, block_idx*100/N_BLOCKS);
        end

        // Summary
        $display("");
        $display("========================================");
        $display("MDR TX Verification Complete");
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
