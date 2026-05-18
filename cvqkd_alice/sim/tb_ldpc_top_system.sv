`timescale 1ns / 1ps

module tb_ldpc_top_system;

    import bg_rom_pkg::*;

    parameter int W = 16;
    parameter int Z = 384;

    logic clk, rst_n, start;
    logic done, success;
    logic [Z*W-1:0] llr_in_bus;
    logic [383:0]   bob_syndrome_in [0:45];
    logic [Z*W-1:0] ram_llr_input [0:67];
    logic [Z-1:0]   ram_key_ref   [0:67];
    int fd_key_ref;
    int fd_u;
    int sim_cycles;
    int errores_bits;
    int dec_match;
    int raw_hard_match;
    int raw_min;
    int raw_max;
    int raw_sum;
    int col_match;
    int raw_mism;
    int rev_mism;
    int raw_first;
    int rev_first;
    int tb_synd_mism;
    int tb_synd_mism_alt;
    int q_par_mism;
    int qmap_mism_0;
    int qmap_mism_1;
    int qmap_mism_2;
    int qmap_mism_3;
    int tb_q_par_mism;
    logic [Z-1:0] tb_q_par;
    logic [67:0] tb_cols_seen;
    int tb_cols_seen_count;
    int tb_col_unknown;
    int tb_col_min;
    int tb_col_max;
    logic [6:0] debug_rd_addr;
    wire  [Z-1:0] debug_rd_data;
    wire  [Z-1:0] key_bits_out;

    ldpc_decoder_top #(
        .W(W), .Z(Z), .MAX_ITER(20)
    ) uut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .done(done), .success(success),
        .llr_in_bus(llr_in_bus),
        .bob_syndrome_in(bob_syndrome_in),
        .key_bits_out(key_bits_out),
        .debug_rd_addr(debug_rd_addr),
        .debug_rd_data(debug_rd_data)
    );



    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("[INFO] Loading MATLAB data (key-space) ...");
        // u_bits.txt: 68 lines, each with 3072 ASCII binary digits (0/1).
        // Each 8-bit LLR is stored as 8 binary chars (MSB-first).
        // Use $fgets to read each line as a string, then parse into 8-bit chunks.
        // We need to load into ram_llr_input (16-bit sign-magnitude format).
        fd_u = $fopen("C:/Users/usser/TFG/cvqkd_code/cvqkd_alice/sim/u_bits.txt", "r");
        if (fd_u == 0) begin
            fd_u = $fopen("u_bits.txt", "r");
        end
        if (fd_u == 0) begin
            fd_u = $fopen("sim/u_bits.txt", "r");
        end
        if (fd_u == 0) begin
            $display("[FATAL] u_bits.txt not found!");
            $finish;
        end
        for (int col = 0; col < 68; col++) begin
            string line;
            int    code;
            int    nchars;
            code = $fgets(line, fd_u);
            // line includes the newline; strip trailing whitespace
            if (code > 0 && line.len() > 0) begin
                while (line.len() > 0) begin
                    byte c;
                    int  ll;
                    c = line[line.len()-1];
                    if (c == 10 || c == 13 || c == 32) begin // \n, \r, space
                        ll = line.len();
                        if (ll >= 2)
                            line = line.substr(0, ll-2);
                        else
                            line = "";
                    end else begin
                        break;
                    end
                end
            end
            nchars = line.len();
            if (nchars != Z*8) begin
                $display("[FATAL] Line %0d length %0d != expected %0d (Z*8)", col, nchars, Z*8);
                $finish;
            end
            for (int v = 0; v < Z; v++) begin
                // Parse 8 binary chars, MSB-first: line[v*8] is bit 7 (sign)
                // 8-bit SM format: sign at bit 7, 7-bit mag at bits [6:0]
                // Convert to 16-bit SM: {sign, 8'b0, 7-bit-mag}
                bit sm_sign;
                bit [6:0] sm_mag;
                sm_sign = (line[v*8 + 0] == "1") ? 1'b1 : 1'b0;
                for (int b = 1; b < 8; b++) begin
                    sm_mag[7-b] = (line[v*8 + b] == "1") ? 1'b1 : 1'b0;
                end
                ram_llr_input[col][v*W +: W] = {
                    sm_sign,
                    {(W-1-7){1'b0}},
                    sm_mag
                };
            end
        end
        $fclose(fd_u);
        $display("[INFO] u_bits.txt loaded (68x%0d LLRs, 8-bit SM -> 16-bit SM)", Z);

        // Try multiple paths for expected_syndrome.txt using $fopen to verify existence
        begin
            int fd_syn;
            string syn_path;
            syn_path = "C:/Users/usser/TFG/cvqkd_code/cvqkd_alice/sim/expected_syndrome.txt";
            fd_syn = $fopen(syn_path, "r");
            if (fd_syn == 0) begin
                syn_path = "sim/expected_syndrome.txt";
                fd_syn = $fopen(syn_path, "r");
            end
            if (fd_syn == 0) begin
                syn_path = "data/expected_syndrome.txt";
                fd_syn = $fopen(syn_path, "r");
            end
            if (fd_syn == 0) begin
                $display("[FATAL] expected_syndrome.txt not found (tried '../data/', 'sim/', 'data/')");
                $finish;
            end
            $fclose(fd_syn);
            $readmemb(syn_path, bob_syndrome_in);
            $display("[INFO] expected_syndrome.txt loaded from %s", syn_path);
        end

        // Try multiple paths for bob_key_ref.txt and remember which one worked
        begin
            string key_ref_path;
            key_ref_path = "";
            fd_key_ref = $fopen("bob_key_ref.txt", "r");
            if (fd_key_ref != 0) begin
                key_ref_path = "bob_key_ref.txt";
            end else begin
                fd_key_ref = $fopen("sim/bob_key_ref.txt", "r");
                if (fd_key_ref != 0) begin
                    key_ref_path = "sim/bob_key_ref.txt";
                end else begin
                    fd_key_ref = $fopen("data/bob_key_ref.txt", "r");
                    if (fd_key_ref != 0) begin
                        key_ref_path = "data/bob_key_ref.txt";
                    end
                end
            end
            if (fd_key_ref != 0) begin
                $fclose(fd_key_ref);
                $readmemb(key_ref_path, ram_key_ref);
                $display("[INFO] bob_key_ref.txt loaded from %s", key_ref_path);
            end else begin
                $display("[WARNING] bob_key_ref.txt not found (tried '.', 'sim/', 'data/'). Using all-zero ref.");
                ram_key_ref = '{default: '0};
            end
        end
    end

    // Track q_sign mapping for row 45 during READ phase
    always @(posedge clk) begin
        if (!rst_n) begin
            qmap_mism_0 <= 0;
            qmap_mism_1 <= 0;
            qmap_mism_2 <= 0;
            qmap_mism_3 <= 0;
            tb_q_par <= '0;
            tb_cols_seen <= '0;
            tb_cols_seen_count <= 0;
            tb_col_unknown <= 0;
            tb_col_min <= 999;
            tb_col_max <= -1;
        end else if (uut.start_row_pulse && uut.row_ptr == 45) begin
            qmap_mism_0 <= 0;
            qmap_mism_1 <= 0;
            qmap_mism_2 <= 0;
            qmap_mism_3 <= 0;
            tb_q_par <= '0;
            tb_cols_seen <= '0;
            tb_cols_seen_count <= 0;
            tb_col_unknown <= 0;
            tb_col_min <= 999;
            tb_col_max <= -1;
        end else if ((uut.state == uut.ST_READ_LAYER || uut.state == uut.ST_READ_DRAIN) && uut.row_ptr == 45 && uut.rom_valid_q) begin
            int c;
            shortint s;
            c = int'(uut.col_idx_q);
            if ($isunknown(uut.col_idx_q)) begin
                tb_col_unknown <= tb_col_unknown + 1;
            end else begin
                if (c < tb_col_min) tb_col_min <= c;
                if (c > tb_col_max) tb_col_max <= c;
            end
            s = BG_ROM[45][c];
            if (s != -1) begin
                if (!$isunknown(uut.col_idx_q)) begin
                    if (!tb_cols_seen[c]) begin
                        tb_cols_seen[c] <= 1'b1;
                        tb_cols_seen_count <= tb_cols_seen_count + 1;
                    end
                end
                for (int i = 0; i < Z; i++) begin
                    logic qv;
                    logic exp0, exp1, exp2, exp3;
                    qv = uut.q_sign_dbg[i];
                    exp0 = ram_key_ref[c][Z-1-((i + int'(s)) % Z)];
                    exp1 = ram_key_ref[c][Z-1-(((i + int'(s)) % Z))]; // same as exp0 (baseline)
                    exp2 = ram_key_ref[c][Z-1-(((Z-1-i) + int'(s)) % Z)];
                    exp3 = ram_key_ref[c][Z-1-(((i - int'(s) + Z) % Z))];
                    if (qv != exp0) qmap_mism_0++;
                    if (qv != exp2) qmap_mism_1++;
                    if (qv != exp3) qmap_mism_2++;
                    tb_q_par[i] <= tb_q_par[i] ^ qv;
                end
            end
        end
    end

    initial begin
        $display("=================================================");
        $display(" INICIANDO TEST DE SISTEMA LDPC (CV-QKD)         ");
        $display("         (key-space decoding)                     ");
        $display("=================================================");

        // raw_hard matches: count how many initial hard decisions (LLR sign)
        // match the reference key (per column)
        raw_hard_match = 0;
        raw_min = Z; raw_max = 0; raw_sum = 0;
        for (int col = 0; col < 68; col++) begin
            col_match = 0;
            for (int b = 0; b < Z; b++) begin
                if (ram_llr_input[col][b*W + (W-1)] == ram_key_ref[col][Z-1-b]) begin
                    col_match = col_match + 1;
                end
            end
            raw_sum += col_match;
            if (col_match < raw_min) raw_min = col_match;
            if (col_match > raw_max) raw_max = col_match;
            if (col == 0) raw_hard_match = col_match;
        end
        $display(" raw_hard_match/Z (col0) = %0d/%0d", raw_hard_match, Z);
        $display(" raw_hard_match/Z min=%0d max=%0d avg=%0d", raw_min, raw_max, raw_sum/68);
        $display(" ref[0][63:0] = %h", ram_key_ref[0][63:0]);

        rst_n = 0; start = 0; sim_cycles = 0;
        errores_bits = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        llr_in_bus = ram_llr_input[0];
        start = 1;
        @(posedge clk);
        start = 0;

        for (int col = 1; col < 68; col++) begin
            @(posedge clk);
            llr_in_bus = ram_llr_input[col];
        end

        $display("[INFO] LLR load complete. Decoding (%0d iter max)...", uut.MAX_ITER);

        // Quick check: verify loaded LLRs (first 4 VNUs of column 0)
        $display("[INFO] Loaded LLR col0 sign bits [3:0] = %b %b %b %b",
                 ram_llr_input[0][15], ram_llr_input[0][31], ram_llr_input[0][47], ram_llr_input[0][63]);

        wait(done == 1'b1);
        $display("[INFO] Decoding done at cycle %0d (iter=%0d)", sim_cycles, uut.iter_cnt);
        $display("[DEBUG] success=%0d, row_fail=%0d", uut.success, uut.row_fail);
        if (uut.row_fail) begin
            $display("[DEBUG] row_fail_idx=%0d raw=%0d rev=%0d", uut.row_fail_idx, uut.row_fail_raw, uut.row_fail_rev);
            raw_mism = 0; rev_mism = 0; raw_first = -1; rev_first = -1;
            for (int i = 0; i < Z; i++) begin
                if (uut.row_syndrome[Z-1-i] != bob_syndrome_in[uut.row_fail_idx][i]) begin
                    raw_mism++;
                    if (raw_first < 0) raw_first = i;
                end
                if (uut.row_syndrome[i] != bob_syndrome_in[uut.row_fail_idx][i]) begin
                    rev_mism++;
                    if (rev_first < 0) rev_first = i;
                end
            end
        $display("[DEBUG] row_fail mismatches: raw=%0d (first=%0d) rev=%0d (first=%0d)", raw_mism, raw_first, rev_mism, rev_first);
        $display("[DEBUG] row45 exp[0:31]=%032b", bob_syndrome_in[uut.row_fail_idx][383 -: 32]);
        $display("[DEBUG] row45 got[0:31]=%032b", uut.row_syndrome[31:0]);
        $display("[DEBUG] row45 got_rev[0:31]=%032b", uut.row_syndrome[383 -: 32]);
        $display("[DEBUG] row45 got_p[0:31]=%032b", uut.row_syndrome_p[31:0]);
        $display("[DEBUG] row45 got_p_rev[0:31]=%032b", uut.row_syndrome_p[383 -: 32]);
        // Recompute row45 syndrome in TB using BG_ROM and key_ref
        tb_synd_mism = 0;
        tb_synd_mism_alt = 0;
        for (int i = 0; i < Z; i++) begin
            logic p;
            logic p_alt;
            p = 1'b0;
            p_alt = 1'b0;
            for (int c = 0; c < 68; c++) begin
                shortint s;
                s = BG_ROM[uut.row_fail_idx][c];
                if (s != -1) begin
                    p ^= ram_key_ref[c][Z-1-((i + int'(s)) % Z)];
                    p_alt ^= ram_key_ref[c][Z-1-(((i - int'(s)) + Z) % Z)];
                end
            end
            if (p != bob_syndrome_in[uut.row_fail_idx][Z-1-i]) begin
                tb_synd_mism++;
            end
            if (p_alt != bob_syndrome_in[uut.row_fail_idx][Z-1-i]) begin
                tb_synd_mism_alt++;
            end
        end
        $display("[DEBUG] TB syndrome mismatches vs file: %0d", tb_synd_mism);
        $display("[DEBUG] TB syndrome mismatches vs file (alt shift): %0d", tb_synd_mism_alt);
        // Compare DUT q_sign parity vs expected for row 45
        q_par_mism = 0;
        for (int i = 0; i < Z; i++) begin
            logic p_q;
            p_q = 1'b0;
            for (int c = 0; c < 68; c++) begin
                shortint s;
                s = BG_ROM[uut.row_fail_idx][c];
                if (s != -1) begin
                    p_q ^= uut.q_sign_dbg[Z-1-((i + int'(s)) % Z)];
                end
            end
            if (p_q != bob_syndrome_in[uut.row_fail_idx][Z-1-i]) begin
                q_par_mism++;
            end
        end
        $display("[DEBUG] q_sign parity mismatches vs file: %0d", q_par_mism);
        $display("[DEBUG] q_sign mapping mismatches: exp0=%0d exp2=%0d exp3=%0d", qmap_mism_0, qmap_mism_1, qmap_mism_2);
        // Compare accumulated TB q_par vs expected syndrome
        tb_q_par_mism = 0;
        for (int i = 0; i < Z; i++) begin
            if (tb_q_par[i] != bob_syndrome_in[uut.row_fail_idx][Z-1-i]) begin
                tb_q_par_mism++;
            end
        end
        $display("[DEBUG] TB accumulated q_par mismatches vs file: %0d", tb_q_par_mism);
        $display("[DEBUG] TB columns seen for row45: %0d", tb_cols_seen_count);
        $display("[DEBUG] TB col_idx_valid_q unknown=%0d min=%0d max=%0d", tb_col_unknown, tb_col_min, tb_col_max);
        $display("[DEBUG] DUT columns seen for row45: %0d", uut.tb_cols_seen_count);
        $display("[DEBUG] DUT columns seen mask row45: %b", uut.tb_cols_seen_mask);
        $display("[DEBUG] DUT col dup events row45: %0d", uut.tb_col_dup_events);
        $display("[DEBUG] DUT col max count row45: %0d", uut.tb_col_max);
        $display("[DEBUG] DUT col counts row45 [0]=%0d [1]=%0d [6]=%0d [10]=%0d [67]=%0d",
                 uut.tb_col_counts[0], uut.tb_col_counts[1], uut.tb_col_counts[6],
                 uut.tb_col_counts[10], uut.tb_col_counts[67]);
        end

        // Read all 68 columns using debug readback port
        // BRAM dout is registered: dout <= ram[rd_addr] at each posedge (NBA).
        // We need TWO @(posedge clk) between setting addr and reading:
        //   T0: set addr
        //   T1 (posedge): RHS evaluated: dout <= ram[T0_addr] (scheduled)
        //   T1 (NBA): dout = ram[T0_addr]
        //   T2 (posedge): dout already = ram[T0_addr] (visible now)
        // Scheme: prime addr=0 with 2 waits, then loop: read, set next, wait 2
        dec_match = 0;
        debug_rd_addr = 0;
        @(posedge clk);  // T1: schedule dout <= ram[0]
        @(posedge clk);  // T2: dout = ram[0] (NBA applied)
        for (int col = 0; col < 68; col++) begin
            logic [Z-1:0] hard_bits;
            int col_match;
            hard_bits = debug_rd_data;  // dout from addr set 2 cycles ago = ram[col]
            // Set NEXT address for next iteration
            debug_rd_addr = 7'((col + 1 < 68) ? col + 1 : 0);
            @(posedge clk);  // T1: schedule dout <= ram[col+1]
            @(posedge clk);  // T2: dout = ram[col+1] (NBA applied, ready for next iter)
            col_match = 0;
            for (int b = 0; b < Z; b++) begin
                if (hard_bits[b] == ram_key_ref[col][Z-1-b]) begin
                    dec_match = dec_match + 1;
                    col_match = col_match + 1;
                end
            end
            if (col_match < Z) begin
                $display("[DEBUG] Column %0d: %0d/%0d match (first32=%h)",
                         col, col_match, Z, hard_bits[31:0]);
            end
        end

        if (success) begin
            $display("[OK] Converged! dec_match/(68*Z) = %0d/%0d (%.2f%%)",
                     dec_match, 68*Z, 100.0*dec_match/(68*Z));
            if (fd_key_ref != 0) begin
                if (dec_match == 68*Z) begin
                    $display("[SUCCESS] All key bits match reference!");
                end else if (dec_match > 68*Z - Z/2) begin
                    $display("[WARNING] Key mismatch: %0d errors out of %0d",
                             68*Z - dec_match, 68*Z);
                    errores_bits = 1;
                end else begin
                    $display("[FAIL] Key mismatch: %0d errors out of %0d",
                             68*Z - dec_match, 68*Z);
                    $display(" key_bits_out[63:0] = %h", key_bits_out[63:0]);
                    $display(" ref0[63:0] = %h", ram_key_ref[0][63:0]);
                    errores_bits = 1;
                end
            end
        end else begin
            $display("[FAIL] No convergence in %0d iterations", uut.MAX_ITER);
            $display(" key_bits_out[63:0] = %h", key_bits_out[63:0]);
            $display(" ref0[63:0] = %h", ram_key_ref[0][63:0]);
            $display(" dec_match/(68*Z) = %0d/%0d", dec_match, 68*Z);
            $display(" raw_hard_match/Z = %0d/%0d", raw_hard_match, Z);
            errores_bits = 1;
        end

        // DEBUG: Check R memory for row45's valid columns
        // Row45 valid columns: 1, 6, 10, 67 (from BG_ROM[45])
        for (int rc = 0; rc < 68; rc++) begin
            if (BG_ROM[45][rc] != -1) begin
                int r_addr_check;
                logic [Z*W-1:0] r_val;
                r_addr_check = 45*68 + rc;
                r_val = uut.r_mem.ram[r_addr_check];
                // Check if r_val is non-zero (has been written)
                if (r_val != '0) begin
                    $display("[DEBUG] R_mem[45][%0d] (addr=%0d) shift=%0d: first 4 words = %h %h %h %h",
                             rc, r_addr_check, BG_ROM[45][rc],
                             r_val[15:0], r_val[31:16], r_val[47:32], r_val[63:48]);
                end else begin
                    $display("[DEBUG] R_mem[45][%0d] (addr=%0d) shift=%0d: ALL ZERO (not updated!)", rc, r_addr_check, BG_ROM[45][rc]);
                end
            end
        end
        // Check P memory: compare col 0's P before and after
        begin
            /* verilator lint_off IMPLICITSTATIC */
            logic [Z*W-1:0] p_col0_init = ram_llr_input[0];
            logic [Z*W-1:0] p_col0_final = uut.p_mem.ram[0];
            /* verilator lint_on IMPLICITSTATIC */
            if (p_col0_final != p_col0_init) begin
                $display("[DEBUG] P_mem[0] CHANGED from initial LLR");
                $display("  init[3:0] signs = %b %b %b %b", p_col0_init[15], p_col0_init[31], p_col0_init[47], p_col0_init[63]);
                $display("  final[3:0] signs = %b %b %b %b", p_col0_final[15], p_col0_final[31], p_col0_final[47], p_col0_final[63]);
            end else begin
                $display("[DEBUG] P_mem[0] UNCHANGED after decoding!");
            end
            // Check R memory column 0 (row 0, col 0)
            begin
                logic [Z*W-1:0] r_col0_final;
                r_col0_final = uut.r_mem.ram[0];
                if (r_col0_final == '0) begin
                    $display("[DEBUG] R_mem[0] (row0,col0) is ALL ZERO");
                end else begin
                    $display("[DEBUG] R_mem[0] (row0,col0) first 4 words = %h %h %h %h",
                             r_col0_final[15:0], r_col0_final[31:16], r_col0_final[47:32], r_col0_final[63:48]);
                end
            end
        end

        $display("=================================================");
        if (errores_bits != 0) begin
            $display("RESULT: FAIL");
        end else begin
            $display("RESULT: PASS");
        end
        #100;
        $finish;
    end

    always @(posedge clk) begin
        sim_cycles = sim_cycles + 1;
    end

endmodule
