`timescale 1ns / 1ps

module mdr_8d_rx #(
    parameter int ADDR_W = 17,
    parameter int DATA_W = 32
)(
    input  logic         clk,
    input  logic         rst_n,

    output logic [ADDR_W-1:0] alice_addr,
    input  logic [DATA_W-1:0] alice_data,

    input  logic         start,
    input  logic [ADDR_W-1:0] base_addr,
    input  logic signed [31:0] m0, m1, m2, m3, m4, m5, m6, m7,
    input  logic signed [31:0] k_llr,

    output logic         ready,
    output logic         valid_out,
    output logic signed [31:0] llr0, llr1, llr2, llr3,
    output logic signed [31:0] llr4, llr5, llr6, llr7
);

    typedef enum logic [4:0] {
        IDLE, RD0, RD1, RD2, RD3, LOAD, NORM,
        MUL_WAIT, LLR_CALC, OUT, DONE
    } state_t;

    state_t state, nxt;
    logic [ADDR_W-1:0] addr;
    logic signed [15:0] pr0, pr1, pr2, pr3, qr0, qr1, qr2, qr3;
    logic signed [31:0] m_reg [0:7];
    logic signed [31:0] k_llr_reg;
    logic signed [31:0] u_reg [0:7];

    logic norm_out_valid, norm_valid;
    logic [17:0] norm_val;
    logic signed [31:0] n0, n1, n2, n3, n4, n5, n6, n7;

    logic mul_valid_in;
    logic mul_valid;
    logic signed [31:0] mu0, mu1, mu2, mu3, mu4, mu5, mu6, mu7;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= nxt;
    end

    always_comb begin
        nxt = state;
        case (state)
            IDLE:      if (start)   nxt = RD0;
            RD0:                     nxt = RD1;
            RD1:                     nxt = RD2;
            RD2:                     nxt = RD3;
            RD3:                     nxt = LOAD;
            LOAD:                    nxt = NORM;
            NORM:      if (norm_valid) nxt = MUL_WAIT;
            MUL_WAIT:  if (mul_valid)  nxt = LLR_CALC;
            LLR_CALC:                  nxt = OUT;
            OUT:                       nxt = DONE;
            DONE:                      nxt = IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) addr <= 0;
        else if (state == IDLE && start) addr <= base_addr;
        else if (state == RD0 || state == RD1 || state == RD2)
            addr <= addr + 1'b1;
    end

    assign alice_addr = addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {qr0, pr0} <= 0;
            {qr1, pr1} <= 0;
            {qr2, pr2} <= 0;
            {qr3, pr3} <= 0;
        end else begin
            case (state)
                RD0: {qr0, pr0} <= alice_data;
                RD1: {qr1, pr1} <= alice_data;
                RD2: {qr2, pr2} <= alice_data;
                RD3: {qr3, pr3} <= alice_data;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_reg[0] <= 0; m_reg[1] <= 0; m_reg[2] <= 0; m_reg[3] <= 0;
            m_reg[4] <= 0; m_reg[5] <= 0; m_reg[6] <= 0; m_reg[7] <= 0;
            k_llr_reg <= 0;
        end else if (start) begin
            m_reg[0] <= m0; m_reg[1] <= m1; m_reg[2] <= m2; m_reg[3] <= m3;
            m_reg[4] <= m4; m_reg[5] <= m5; m_reg[6] <= m6; m_reg[7] <= m7;
            k_llr_reg <= k_llr;
        end
    end

    norm_8d #(.W(16)) norm_inst (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(state == LOAD),
        .x0(pr0), .x1(qr0), .x2(pr1), .x3(qr1),
        .x4(pr2), .x5(qr2), .x6(pr3), .x7(qr3),
        .valid_out(norm_out_valid),
        .norm(norm_val)
    );

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

    assign mul_valid_in = (state == NORM) && norm_valid;

    mat_vec_mul_8x8 mul_inst (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(mul_valid_in),
        .v0(n0), .v1(n1), .v2(n2), .v3(n3),
        .v4(n4), .v5(n5), .v6(n6), .v7(n7),
        .m0(m_reg[0]), .m1(m_reg[1]), .m2(m_reg[2]), .m3(m_reg[3]),
        .m4(m_reg[4]), .m5(m_reg[5]), .m6(m_reg[6]), .m7(m_reg[7]),
        .valid_out(mul_valid),
        .u0(mu0), .u1(mu1), .u2(mu2), .u3(mu3),
        .u4(mu4), .u5(mu5), .u6(mu6), .u7(mu7)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            u_reg[0] <= 0; u_reg[1] <= 0; u_reg[2] <= 0; u_reg[3] <= 0;
            u_reg[4] <= 0; u_reg[5] <= 0; u_reg[6] <= 0; u_reg[7] <= 0;
        end else if (mul_valid) begin
            u_reg[0] <= mu0; u_reg[1] <= mu1; u_reg[2] <= mu2; u_reg[3] <= mu3;
            u_reg[4] <= mu4; u_reg[5] <= mu5; u_reg[6] <= mu6; u_reg[7] <= mu7;
        end
    end

    function automatic logic signed [31:0] q31_mul(
        input logic signed [31:0] a,
        input logic signed [31:0] b
    );
        logic signed [63:0] p;
        p = $signed(a) * $signed(b);
        p = p >>> 31;
        if (p > $signed(64'h000000007FFFFFFF)) return 32'h7FFFFFFF;
        else if (p < $signed(64'hFFFFFFFF80000000)) return 32'h80000000;
        else return p[31:0];
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {llr0, llr1, llr2, llr3, llr4, llr5, llr6, llr7} <= 0;
            valid_out <= 0;
        end else begin
            valid_out <= (state == OUT);
            if (state == LLR_CALC) begin
                llr0 <= q31_mul(k_llr_reg, u_reg[0]);
                llr1 <= q31_mul(k_llr_reg, u_reg[1]);
                llr2 <= q31_mul(k_llr_reg, u_reg[2]);
                llr3 <= q31_mul(k_llr_reg, u_reg[3]);
                llr4 <= q31_mul(k_llr_reg, u_reg[4]);
                llr5 <= q31_mul(k_llr_reg, u_reg[5]);
                llr6 <= q31_mul(k_llr_reg, u_reg[6]);
                llr7 <= q31_mul(k_llr_reg, u_reg[7]);
            end
        end
    end

    assign ready = (state == IDLE);

endmodule
