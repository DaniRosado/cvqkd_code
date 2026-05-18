`timescale 1ns / 1ps

module ldpc_bram_block #(
    parameter int Z = 384,
    parameter int W = 8,
    parameter int DEPTH = 68
)(
    input  logic                 clk,
    input  logic [$clog2(DEPTH)-1:0] rd_addr,
    input  logic [$clog2(DEPTH)-1:0] wr_addr,
    input  logic [Z*W-1:0]           din,
    input  logic                     we,
    output logic [Z*W-1:0]           dout
);

    (* ram_style = "block" *)
    logic [Z*W-1:0] ram [0:DEPTH-1] = '{default: '0};

    always_ff @(posedge clk) begin
        if (we) begin
            ram[wr_addr] <= din;
        end
        dout <= ram[rd_addr];
    end

endmodule
