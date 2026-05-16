SIM=sim
RTL=rtl
BLD=build
DATA=../cvqkd_matlab/data

VSRC=$(RTL)/norm_8d.sv $(RTL)/normalize_8d.sv \
     $(RTL)/reciprocal_lut_256.sv $(RTL)/mat_vec_mul_8x8.sv \
     $(RTL)/mat_vec_add_8x8.sv $(RTL)/bpsk_mapper.sv \
     $(RTL)/mdr_8d_tx.sv $(RTL)/mdr_8d_rx.sv

TB_TX    = $(SIM)/tb_mdr_8d_tx.sv
TB_RX    = $(SIM)/tb_mdr_8d_rx.sv
TB_SYSTEM = $(SIM)/tb_cvqkd_system.sv

.PHONY: all tx rx system tx_run rx_run system_run clean

all: tx_run rx_run system_run

tx: $(BLD)/tb_mdr_8d_tx
rx: $(BLD)/tb_mdr_8d_rx
system: $(BLD)/tb_cvqkd_system

$(BLD)/tb_mdr_8d_tx: $(TB_TX) $(VSRC)
	mkdir -p $(BLD)
	iverilog -g2012 -o $@ $< $(RTL)/mdr_8d_tx.sv \
		$(RTL)/norm_8d.sv $(RTL)/normalize_8d.sv \
		$(RTL)/reciprocal_lut_256.sv $(RTL)/mat_vec_mul_8x8.sv \
		$(RTL)/mat_vec_add_8x8.sv $(RTL)/bpsk_mapper.sv

$(BLD)/tb_mdr_8d_rx: $(TB_RX) $(VSRC)
	mkdir -p $(BLD)
	iverilog -g2012 -o $@ $< $(RTL)/mdr_8d_rx.sv \
		$(RTL)/norm_8d.sv $(RTL)/normalize_8d.sv \
		$(RTL)/reciprocal_lut_256.sv $(RTL)/mat_vec_mul_8x8.sv

$(BLD)/tb_cvqkd_system: $(TB_SYSTEM) $(VSRC)
	mkdir -p $(BLD)
	iverilog -g2012 -o $@ $< \
		$(RTL)/mdr_8d_tx.sv $(RTL)/mdr_8d_rx.sv \
		$(RTL)/norm_8d.sv $(RTL)/normalize_8d.sv \
		$(RTL)/reciprocal_lut_256.sv $(RTL)/mat_vec_mul_8x8.sv \
		$(RTL)/mat_vec_add_8x8.sv $(RTL)/bpsk_mapper.sv

tx_run: tx
	./$(BLD)/tb_mdr_8d_tx

rx_run: rx
	./$(BLD)/tb_mdr_8d_rx

system_run: system
	./$(BLD)/tb_cvqkd_system

clean:
	rm -rf $(BLD)
