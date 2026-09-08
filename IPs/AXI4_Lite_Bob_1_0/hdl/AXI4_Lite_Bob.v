
`timescale 1 ns / 1 ps

	module AXI4_Lite_Bob #
	(
		// Users to add parameters here
		parameter integer ADC_WIDHT = 16,
		parameter integer NUM_SAMPLES = 26112/2,
		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 5
	)
	(
		// Users to add ports here

		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready
	);
// Instantiation of Axi Bus Interface S00_AXI
	AXI4_Lite_Bob_slave_lite_v1_0_S00_AXI # ( 
		.C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
	) AXI4_Lite_Bob_slave_lite_v1_0_S00_AXI_inst (
		.p_in(p_in),
		.q_in(q_in),
		.valid_in(valid_in),
		.mask_valid(mask_valid),
		.mask_bit(mask_bit),
		.alice_stream_valid(alice_stream_valid),
		.alice_stream_data(alice_stream_data),
		.trng_data(trng_data),
		.calib_VarA(calib_VarA),
		.T_final_out(T_final_out),
		.T_sqrt_out(T_sqrt_out),
		.sigma_sq_out(sigma_sq_out),
		.sigma_out(sigma_out),
		.num_samples_out(num_samples_out),
		.done_est(done_est),
		.mdr_valid(mdr_valid),
		.mdr_m_out(mdr_m_out),
		.syndrome_done(syndrome_done),
		.syndrome_valid(syndrome_valid),
		.syndrome_row_idx(syndrome_row_idx),
		.syndrome_data(syndrome_data),
		.S_AXI_ACLK(s00_axi_aclk),
		.S_AXI_ARESETN(s00_axi_aresetn),
		.S_AXI_AWADDR(s00_axi_awaddr),
		.S_AXI_AWPROT(s00_axi_awprot),
		.S_AXI_AWVALID(s00_axi_awvalid),
		.S_AXI_AWREADY(s00_axi_awready),
		.S_AXI_WDATA(s00_axi_wdata),
		.S_AXI_WSTRB(s00_axi_wstrb),
		.S_AXI_WVALID(s00_axi_wvalid),
		.S_AXI_WREADY(s00_axi_wready),
		.S_AXI_BRESP(s00_axi_bresp),
		.S_AXI_BVALID(s00_axi_bvalid),
		.S_AXI_BREADY(s00_axi_bready),
		.S_AXI_ARADDR(s00_axi_araddr),
		.S_AXI_ARPROT(s00_axi_arprot),
		.S_AXI_ARVALID(s00_axi_arvalid),
		.S_AXI_ARREADY(s00_axi_arready),
		.S_AXI_RDATA(s00_axi_rdata),
		.S_AXI_RRESP(s00_axi_rresp),
		.S_AXI_RVALID(s00_axi_rvalid),
		.S_AXI_RREADY(s00_axi_rready)
	);

	// Add user logic here
	cvqkd_bob_subsystem_top #(
		.ADC_WIDHT(ADC_WIDHT),
		.NUM_SAMPLES(NUM_SAMPLES)
	) cvqkd_bob_subsystem_top_inst (
		.clk(s00_axi_aclk),
		.rst_N(s00_axi_aresetn),
		.p_in(p_in),
		.q_in(q_in),
		.valid_in(valid_in),
		.mask_valid(mask_valid),
		.mask_bit(mask_bit),
		.alice_stream_valid(alice_stream_valid),
		.alice_stream_data(alice_stream_data),
		.trng_data(trng_data),
		.calib_VarA(calib_VarA),
		.T_final_out(T_final_out),
		.T_sqrt_out(T_sqrt_out),
		.sigma_sq_out(sigma_sq_out),
		.sigma_out(sigma_out),
		.num_samples_out(num_samples_out),
		.done_est(done_est),
		.mdr_valid(mdr_valid),
		.mdr_m_out(mdr_m_out),
		.syndrome_done(syndrome_done),
		.syndrome_valid(syndrome_valid),
		.syndrome_row_idx(syndrome_row_idx),
		.syndrome_data(syndrome_data)
	);	
	// User logic ends

	endmodule
