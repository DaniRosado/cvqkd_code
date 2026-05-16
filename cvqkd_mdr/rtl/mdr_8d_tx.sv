`timescale 1ns / 1ps

module mdr_8d_tx #(
    parameter int ADDR_W = 17,
    parameter int DATA_W = 32
)(
    input  logic         clk,
    input  logic         rst_n,

    output logic [ADDR_W-1:0] bram_addr,
    input  logic [DATA_W-1:0] bram_data,

    input  logic         start,
    input  logic [ADDR_W-1:0] base_addr,
    input  logic [7:0]   random_bits,
    output logic         ready,
    output logic         valid_out,
    output logic signed [31:0] m0, m1, m2, m3, m4, m5, m6, m7
);

    typedef enum logic [4:0] {
        IDLE, RD0, RD1, RD2, RD3, LOAD, WAIT_NORM, OUT, DONE
    } state_t;

    state_t state, nxt;
    logic [ADDR_W-1:0] addr;
    logic signed [15:0] pr0, pr1, pr2, pr3, qr0, qr1, qr2, qr3;
    logic signed [31:0] u0, u1, u2, u3, u4, u5, u6, u7;
    logic norm_out_valid, norm_valid;
    logic [17:0] norm_val;
    logic signed [31:0] n0, n1, n2, n3, n4, n5, n6, n7;

    // FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= nxt;
    end

    always_comb begin
        nxt = state;
        case (state)
            IDLE:     if (start) nxt = RD0;
            RD0:                  nxt = RD1;
            RD1:                  nxt = RD2;
            RD2:                  nxt = RD3;
            RD3:                  nxt = LOAD;
            LOAD:                 nxt = WAIT_NORM;
            WAIT_NORM: if (norm_valid) nxt = OUT;
            OUT:                  nxt = DONE;
            DONE:                 nxt = IDLE;
        endcase
    end

    // Address: set in IDLE, increment after each capture
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) addr <= 0;
        else if (state == IDLE && start) addr <= base_addr;
        else if (state == RD0 || state == RD1 || state == RD2)
                                       addr <= addr + 1'b1;
    end

    assign bram_addr = addr;

    // Capture BRAM data: combinational BRAM reflects addr change immediately
    // IDLE: set addr → data stable by RD0 posedge
    // RD0: capture mem[base_addr] ✓, inc addr
    // RD1: capture mem[base_addr+1] ✓, inc addr
    // RD2: capture mem[base_addr+2] ✓, inc addr
    // RD3: capture mem[base_addr+3] ✓
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {qr0, pr0} <= 0;
            {qr1, pr1} <= 0;
            {qr2, pr2} <= 0;
            {qr3, pr3} <= 0;
        end else begin
            case (state)
                RD0: {qr0, pr0} <= bram_data;
                RD1: {qr1, pr1} <= bram_data;
                RD2: {qr2, pr2} <= bram_data;
                RD3: {qr3, pr3} <= bram_data;
            endcase
        end
    end

    // BPSK map random bits on start
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {u0, u1, u2, u3, u4, u5, u6, u7} <= 0;
        end else if (start) begin
            u0 <= random_bits[0] ? 32'h80000000 : 32'h7FFFFFFF;
            u1 <= random_bits[1] ? 32'h80000000 : 32'h7FFFFFFF;
            u2 <= random_bits[2] ? 32'h80000000 : 32'h7FFFFFFF;
            u3 <= random_bits[3] ? 32'h80000000 : 32'h7FFFFFFF;
            u4 <= random_bits[4] ? 32'h80000000 : 32'h7FFFFFFF;
            u5 <= random_bits[5] ? 32'h80000000 : 32'h7FFFFFFF;
            u6 <= random_bits[6] ? 32'h80000000 : 32'h7FFFFFFF;
            u7 <= random_bits[7] ? 32'h80000000 : 32'h7FFFFFFF;
        end
    end

    // norm_8d: compute sqrt(sum of squares)
    norm_8d #(.W(16)) norm_inst (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(state == LOAD),
        .x0(pr0), .x1(qr0), .x2(pr1), .x3(qr1),
        .x4(pr2), .x5(qr2), .x6(pr3), .x7(qr3),
        .valid_out(norm_out_valid),
        .norm(norm_val)
    );

    // normalize_8d: divide each component by norm
    normalize_8d #(.W(16)) norm8_inst (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(norm_out_valid),
        .x0(pr0), .x1(qr0), .x2(pr1), .x3(qr1),
        .x4(pr2), .x5(qr2), .x6(pr3), .x7(qr3),
        .norm(norm_val),
        .valid_out(norm_valid),
        .n0(n0), .n1(n1), .n2(n2), .n3(n3),
        .n4(n4), .n5(n5), .n6(n6), .n7(n7)
    );

    // mat_vec_add_8x8: combinational m = M' × U
    mat_vec_add_8x8 add_inst (
        .v0(n0), .v1(n1), .v2(n2), .v3(n3),
        .v4(n4), .v5(n5), .v6(n6), .v7(n7),
        .u0(u0), .u1(u1), .u2(u2), .u3(u3),
        .u4(u4), .u5(u5), .u6(u6), .u7(u7),
        .m0(m0), .m1(m1), .m2(m2), .m3(m3),
        .m4(m4), .m5(m5), .m6(m6), .m7(m7)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid_out <= 0;
        else        valid_out <= (state == OUT);
    end

    assign ready = (state == IDLE);

endmodule
