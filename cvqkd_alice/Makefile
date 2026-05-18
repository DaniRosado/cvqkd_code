# Makefile para compilación y simulación de cvqkd_alice (LDPC Decoder)
# Uso:
#   make all        - Compila todos los módulos y testbenches
#   make tb_vnu    - Compila y ejecuta testbench VNU
#   make tb_cnu    - Compila y ejecuta testbench CNU
#   make tb_shifter - Compila y ejecuta testbench Barrel Shifter
#   make tb_system - Compila y ejecuta testbench del sistema completo
#   make clean     - Limpia archivos generados
#   make help      - Muestra esta ayuda

# === Herramientas ===
# En Windows (Git Bash), establecer antes: export XILINX_VIVADO=/c/AMDDesignTools/2025.2/Vivado
# O usar: make XILINX_VIVADO="C:/AMDDesignTools/2025.2/Vivado"
ifeq ($(OS),Windows_NT)
    XILINX_VIVADO ?= C:/AMDDesignTools/2025.2/Vivado
else
    XILINX_VIVADO ?= /tools/Xilinx/Vivado/2025.2
endif
XVLOG   ?= $(XILINX_VIVADO)/bin/xvlog
XELAB   ?= $(XILINX_VIVADO)/bin/xelab
XSIM    ?= $(XILINX_VIVADO)/bin/xsim
VERILATOR ?= verilator

SOURCES_DIR = rtl
SIM_DIR     = sim
WORK_DIR    = xsim_work
OBJ_DIR     = obj_dir

# Archivos fuentes en orden de dependencia
SOURCES = \
	$(SOURCES_DIR)/bg_rom_pkg.sv \
	$(SOURCES_DIR)/barrel_shifter_word.sv \
	$(SOURCES_DIR)/cnu_serial_minsum.sv \
	$(SOURCES_DIR)/cnu_cell.sv \
	$(SOURCES_DIR)/cnu_min_sum_array.sv \
	$(SOURCES_DIR)/vnu_processor.sv \
	$(SOURCES_DIR)/ldpc_bram_block.sv \
	$(SOURCES_DIR)/ldpc_rom_controller.sv \
	$(SOURCES_DIR)/ldpc_layer_datapath.sv \
	$(SOURCES_DIR)/ldpc_decoder_top.sv

# Testbenches
TB_VNU     = $(SIM_DIR)/tb_vnu_processor.sv
TB_CNU     = $(SIM_DIR)/tb_cnu_serial_minsum.sv
TB_SHIFTER = $(SIM_DIR)/tb_barrel_shifter_word.sv
TB_SYSTEM  = $(SIM_DIR)/tb_ldpc_top_system.sv

# Opciones de compilación
XVLOG_OPTS = --sv -d SIMULATION
XELAB_OPTS = -debug typical
XSIM_OPTS  = -runall

# Nombre de los work libraries
WORK_VNU     = work.tb_vnu_processor
WORK_CNU     = work.tb_cnu_serial_minsum
WORK_SHIFTER = work.tb_barrel_shifter_word
WORK_SYSTEM  = work.tb_ldpc_top_system

.PHONY: all tb_vnu tb_cnu tb_shifter tb_system clean help check_xvlog lint tb_system_v

all: tb_vnu tb_cnu tb_shifter tb_system

check_xvlog:
	@if ! command -v $(XVLOG) &> /dev/null; then \
		echo "ERROR: xvlog no encontrado en $(XVLOG)"; \
		echo "       Establecer XILINX_VIVADO con la ruta correcta"; \
		echo "       Ej: make XILINX_VIVADO=/opt/Xilinx/Vivado/2024.1"; \
		exit 1; \
	fi

# Compilar fuentes comunes
$(WORK_DIR)/sources_compiled: $(SOURCES) | check_xvlog
	@mkdir -p $(WORK_DIR)
	@echo "===== Compilando fuentes LDPC ====="
	$(XVLOG) $(XVLOG_OPTS) --work work $(SOURCES) 2>&1 | tee $(WORK_DIR)/xvlog_sources.log
	@touch $@

# --- VNU Processor Testbench ---
tb_vnu: $(WORK_DIR)/sources_compiled
	@echo "===== Compilando testbench VNU ====="
	$(XVLOG) $(XVLOG_OPTS) --work work $(TB_VNU) 2>&1 | tee $(WORK_DIR)/xvlog_tb_vnu.log
	$(XELAB) $(XELAB_OPTS) $(WORK_VNU) 2>&1 | tee $(WORK_DIR)/xelab_tb_vnu.log
	@echo "===== Ejecutando simulación VNU ====="
	$(XSIM) $(WORK_VNU) $(XSIM_OPTS) 2>&1 | tee $(WORK_DIR)/xsim_tb_vnu.log
	@echo "===== VNU done ====="

# --- CNU Serial Min-Sum Testbench ---
tb_cnu: $(WORK_DIR)/sources_compiled
	@echo "===== Compilando testbench CNU ====="
	$(XVLOG) $(XVLOG_OPTS) --work work $(TB_CNU) 2>&1 | tee $(WORK_DIR)/xvlog_tb_cnu.log
	$(XELAB) $(XELAB_OPTS) $(WORK_CNU) 2>&1 | tee $(WORK_DIR)/xelab_tb_cnu.log
	@echo "===== Ejecutando simulación CNU ====="
	$(XSIM) $(WORK_CNU) $(XSIM_OPTS) 2>&1 | tee $(WORK_DIR)/xsim_tb_cnu.log
	@echo "===== CNU done ====="

# --- Barrel Shifter Testbench ---
tb_shifter: $(WORK_DIR)/sources_compiled
	@echo "===== Compilando testbench Barrel Shifter ====="
	$(XVLOG) $(XVLOG_OPTS) --work work $(TB_SHIFTER) 2>&1 | tee $(WORK_DIR)/xvlog_tb_shifter.log
	$(XELAB) $(XELAB_OPTS) $(WORK_SHIFTER) 2>&1 | tee $(WORK_DIR)/xelab_tb_shifter.log
	@echo "===== Ejecutando simulación Barrel Shifter ====="
	$(XSIM) $(WORK_SHIFTER) $(XSIM_OPTS) 2>&1 | tee $(WORK_DIR)/xsim_tb_shifter.log
	@echo "===== Shifter done ====="

# --- System Testbench (top-level) ---
tb_system: $(WORK_DIR)/sources_compiled
	@echo "===== Compilando testbench del sistema ====="
	cd $(SIM_DIR) && $(XVLOG) $(XVLOG_OPTS) --work work ../$(TB_SYSTEM) 2>&1 | tee ../$(WORK_DIR)/xvlog_tb_system.log
	cd $(SIM_DIR) && $(XELAB) $(XELAB_OPTS) $(WORK_SYSTEM) 2>&1 | tee ../$(WORK_DIR)/xelab_tb_system.log
	@echo "===== Ejecutando simulación del sistema ====="
	cd $(SIM_DIR) && $(XSIM) $(WORK_SYSTEM) $(XSIM_OPTS) 2>&1 | tee ../$(WORK_DIR)/xsim_tb_system.log
	@echo "===== System done ====="

# === Verilator (Open-Source) ===
lint:
	@echo "===== Verilator Lint ====="
	$(VERILATOR) --lint-only -Wno-TIMESCALEMOD --top ldpc_decoder_top $(SOURCES) 2>&1
	@echo "===== Lint OK ====="

tb_system_v:
	@echo "===== Compilando con Verilator ====="
	$(VERILATOR) --timing --trace --binary -Wno-TIMESCALEMOD --top tb_ldpc_top_system $(SOURCES) $(TB_SYSTEM) 2>&1
	@echo "===== Ejecutando simulación (desde sim/) ====="
	cd $(SIM_DIR) && ../$(OBJ_DIR)/Vtb_ldpc_top_system
	@echo "===== Simulation done ====="

clean:
	@echo "===== Limpiando archivos generados ====="
	rm -rf $(WORK_DIR) $(OBJ_DIR) xsim.dir .Xil
	rm -f *.log *.jou *.str
	rm -f webtalk* xvlog* xelab* xsim*
	@echo "===== Clean done ====="

help:
	@echo "Uso: make <target>"
	@echo ""
	@echo "Targets disponibles:"
	@echo "  all          Compila y ejecuta todos los testbenches"
	@echo "  tb_vnu       Testbench del VNU Processor"
	@echo "  tb_cnu       Testbench del CNU Serial Min-Sum"
	@echo "  tb_shifter   Testbench del Barrel Shifter Word"
	@echo "  tb_system    Testbench del sistema LDPC completo"
	@echo "  lint         Verilator lint (rápido, sin simulación)"
	@echo "  tb_system_v  Simulación con Verilator (open-source)"
	@echo "  clean        Limpia archivos generados"
	@echo "  help         Muestra esta ayuda"
	@echo ""
	@echo "Variables:"
	@echo "  XILINX_VIVADO  Ruta a Vivado (def: /tools/Xilinx/Vivado/2025.2)"
