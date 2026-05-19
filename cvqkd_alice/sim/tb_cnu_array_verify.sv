`timescale 1ns / 1ps

module tb_cnu_array_verify;

    parameter int Z = 384;
    parameter int W = 16;
    parameter int COL_W = 7;
    parameter int N_COLS = 68;

    logic clk, rst_n;
    logic start_row, phase, valid_in;
    logic [COL_W-1:0] col_idx;

    logic [Z*W-1:0] q_bus;
    logic [Z*W-1:0] q_bus_current;
    logic [Z*W-1:0] p_bus;
    logic [Z-1:0]   syndrome_row;

    wire [Z*W-1:0] r_new_bus;
    wire [Z-1:0]   row_syndrome;
    wire [Z-1:0]   row_syndrome_p;

    int total_mismatches = 0;
    int debug_ones;

    // q_bus_current is q_bus delayed by 1 cycle
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            q_bus_current <= '0;
        else
            q_bus_current <= q_bus;
    end

    // Reference memories
    logic [Z*W-1:0] ram_q_in [0:N_COLS-1];
    logic [Z*W-1:0] ram_p_in [0:N_COLS-1];
    logic [383:0]   ram_syndrome_bob [0:45];

    // MATLAB-style reference model: compute expected r_new per column
    logic [W-2:0] ref_min1 [0:Z-1];
    logic [W-2:0] ref_min2 [0:Z-1];
    logic [COL_W-1:0] ref_min1_idx [0:Z-1];
    logic [0:Z-1] ref_total_sign;

    function automatic void compute_reference();
        localparam logic [W-2:0] MAX_MAG = '1;
        for (int z = 0; z < Z; z++) begin
            ref_min1[z] = MAX_MAG;
            ref_min2[z] = MAX_MAG;
            ref_min1_idx[z] = '0;
            ref_total_sign[z] = syndrome_row[z];
            for (int c = 0; c < N_COLS; c++) begin
                logic sign = ram_q_in[c][z*W + (W-1)];
                logic [W-2:0] mag = ram_q_in[c][z*W +: (W-1)];
                ref_total_sign[z] = ref_total_sign[z] ^ sign;
                if (mag < ref_min1[z]) begin
                    ref_min2[z] = ref_min1[z];
                    ref_min1[z] = mag;
                    ref_min1_idx[z] = COL_W'(c);
                end else if (mag < ref_min2[z]) begin
                    ref_min2[z] = mag;
                end
            end
        end
    endfunction

    function automatic logic [W-1:0] compute_r_new(int z, int c);
        logic [W-2:0] raw_mag;
        logic [W-2:0] norm_mag;
        raw_mag = (COL_W'(c) == ref_min1_idx[z]) ? ref_min2[z] : ref_min1[z];
        norm_mag = raw_mag - (raw_mag >> 2);
        // During WRITE, q_bus='0 so q_sign_for_r=0.
        // RTL: r_new = total_sign_arr ^ 0 = reg_total_sign_q (accumulated from READ)
        // ref_total_sign = syndrome ^ all q_signs = reg_total_sign_q
        compute_r_new = {ref_total_sign[z], norm_mag};
    endfunction

    // DUT
    cnu_min_sum_array #(
        .Z(Z), .W(W), .COL_W(COL_W)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start_row(start_row),
        .phase(phase),
        .valid_in(valid_in),
        .q_bus(q_bus),
        .q_bus_current(q_bus_current),
        .p_bus(p_bus),
        .col_idx(col_idx),
        .syndrome_row(syndrome_row),
        .r_new_bus(r_new_bus),
        .row_syndrome(row_syndrome),
        .row_syndrome_p(row_syndrome_p)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("=============================================");
        $display(" CNU Array Verification (Golden Reference)");
        $display("=============================================");

        // Load test vectors
        $readmemb("C:/Users/usser/TFG/cvqkd_code/cvqkd_matlab/data/cnu_tb_q_in.txt", ram_q_in);
        $readmemb("C:/Users/usser/TFG/cvqkd_code/cvqkd_matlab/data/cnu_tb_p_in.txt", ram_p_in);
        $readmemb("C:/Users/usser/TFG/cvqkd_code/cvqkd_matlab/data/expected_syndrome.txt", ram_syndrome_bob);

        // Initialize
        rst_n = 0; start_row = 0; phase = 0; valid_in = 0; col_idx = 0;
        q_bus = '0; p_bus = '0; syndrome_row = '0;
        #50 rst_n = 1;
        @(posedge clk);  // Wait one clean cycle after reset

        // Start row 0
        syndrome_row = {<<{ram_syndrome_bob[0]}};
        start_row = 1;
        @(posedge clk);
        start_row = 0;

        // READ phase
        for (int c = 0; c < N_COLS; c++) begin
            valid_in = 1; phase = 0; col_idx = c;
            q_bus = ram_q_in[c];
            p_bus = ram_p_in[c];
            @(posedge clk);
        end
        valid_in = 0;
        @(posedge clk);

        // Compute golden reference
        compute_reference();

        // WRITE phase - compare
        phase = 1;
        #50;

        $display("[INFO] Comparing RTL output vs golden reference...");

        // Debug: print reference for node 0
        $display("[REF] Node 0: ref_total_sign=%b, ref_min1=%d, ref_min2=%d, ref_min1_idx=%d",
                 ref_total_sign[0], ref_min1[0], ref_min2[0], ref_min1_idx[0]);

        // Count 1-bits in q_sign for node 0
        debug_ones = 0;
        for (int cc = 0; cc < N_COLS; cc++) begin
            if (ram_q_in[cc][0*W + (W-1)]) debug_ones++;
        end
        $display("[DBG] Node 0: syndrome=%b, q_sign ones=%d (parity=%b), expected reg=%b",
                 syndrome_row[0], debug_ones, debug_ones[0], syndrome_row[0] ^ debug_ones[0]);

        for (int c = 0; c < N_COLS; c++) begin
            col_idx = c;
            @(posedge clk);

            if (c == 0) begin
                $display("[DBG] Col 0: RTL r_new[0]=%b, ref=%b",
                         r_new_bus[0*W +: W], compute_r_new(0, 0));
            end

            for (int z = 0; z < Z; z++) begin
                logic [W-1:0] r_got;
                logic [W-1:0] r_exp;
                r_got = r_new_bus[z*W +: W];
                r_exp = compute_r_new(z, c);

                if (r_got !== r_exp) begin
                    total_mismatches++;
                    if (total_mismatches <= 3) begin
                        $display("[FAIL] Col %0d, Node %0d: Expected %b, Got %b",
                                 c, z, r_exp, r_got);
                    end
                end
            end
        end

        if (total_mismatches == 0) begin
            $display("=================================================");
            $display("[SUCCESS] CNU ARRAY VERIFIED! All 68 columns match.");
            $display("=================================================");
        end else begin
            $display("=================================================");
            $display("[FAIL] %0d mismatches found", total_mismatches);
            $display("=================================================");
        end

        $display("[TB] Test finished.");
        $finish;
    end
endmodule
