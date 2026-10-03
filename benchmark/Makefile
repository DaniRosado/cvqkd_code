# Makefile para Benchmarks CV-QKD (Alice y Bob): Hardware FPGA vs CPU Software

# Rutas de la instalación de Vitis y de la plataforma de Bob (PYNQ-Z2) para los binarios ARM:
#   make arm XILINX_VITIS=/ruta/a/Vitis VITIS_WS=/ruta/al/workspace
XILINX_VITIS ?= $(HOME)/AMD/Xilin/2025.2/Vitis
VITIS_WS     ?= $(HOME)/VitisProyects
ARM_BIN  = $(XILINX_VITIS)/gnu/aarch32/lin/gcc-arm-none-eabi/bin
BSP      = $(VITIS_WS)/cvqkd_bob/cvqkd_bob_platform/export/cvqkd_bob_platform/sw/standalone_ps7_cortexa9_0

CC_HOST  = gcc
CC_ARM   = $(ARM_BIN)/arm-none-eabi-gcc
SIZE_ARM = $(ARM_BIN)/arm-none-eabi-size

# Módulo de seguridad, vectores de MATLAB y script de enlazado: los del firmware de Bob
BOB_SW = ../cvqkd_bob/sw

CFLAGS_HOST = -O3 -Wall -Wextra -I. -I$(BOB_SW)
CFLAGS_ARM  = -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -O3 -Wall -Wextra -I. -I$(BOB_SW) \
              -isystem $(BSP)/include -DPLATFORM_ARM_BAREMETAL=1

LDFLAGS_ARM = -specs=$(BSP)/Xilinx.spec -T $(BOB_SW)/lscript.ld -L$(BSP)/lib \
              -Wl,--start-group,-lxilstandalone,-lxiltimer,-lxil,-lgcc,-lc,-lm,--end-group

all: host arm bob_host bob_arm

# ------------------------------------------------------------------------------
# ALICE BENCHMARK (LDPC Error Correction Decoder)
# ------------------------------------------------------------------------------
host: bench_host

bench_host: cvqkd_cpu_benchmark.c cvqkd_benchmark_data.h
	$(CC_HOST) $(CFLAGS_HOST) cvqkd_cpu_benchmark.c -o bench_host -lm
	@echo ">>> Compilado bench_host (Alice x86-64) con exito!"

arm: cvqkd_benchmark_pynq_arm.elf

bench_arm.o: cvqkd_cpu_benchmark.c cvqkd_benchmark_data.h
	$(CC_ARM) $(CFLAGS_ARM) -c cvqkd_cpu_benchmark.c -o bench_arm.o

cvqkd_benchmark_pynq_arm.elf: bench_arm.o
	$(CC_ARM) $(CFLAGS_ARM) bench_arm.o $(LDFLAGS_ARM) -o cvqkd_benchmark_pynq_arm.elf
	@echo ">>> Compilado cvqkd_benchmark_pynq_arm.elf (Alice ARM Cortex-A9) con exito!"

# ------------------------------------------------------------------------------
# BOB BENCHMARK (Phase Compensation + DSP Estimator + MDR 8D + Syndrome + Holevo)
# ------------------------------------------------------------------------------
bob_host: bench_bob_host

bench_bob_host: cvqkd_bob_cpu_benchmark.c $(BOB_SW)/cvqkd_security.c $(BOB_SW)/cvqkd_security.h $(BOB_SW)/matlab_vectors.h cvqkd_benchmark_data.h
	$(CC_HOST) $(CFLAGS_HOST) cvqkd_bob_cpu_benchmark.c $(BOB_SW)/cvqkd_security.c -o bench_bob_host -lm
	@echo ">>> Compilado bench_bob_host (Bob x86-64) con exito!"

bob_arm: cvqkd_bob_benchmark_pynq_arm.elf

bench_bob_arm.o: cvqkd_bob_cpu_benchmark.c $(BOB_SW)/cvqkd_security.h $(BOB_SW)/matlab_vectors.h cvqkd_benchmark_data.h
	$(CC_ARM) $(CFLAGS_ARM) -c cvqkd_bob_cpu_benchmark.c -o bench_bob_arm.o

cvqkd_security_arm.o: $(BOB_SW)/cvqkd_security.c $(BOB_SW)/cvqkd_security.h
	$(CC_ARM) $(CFLAGS_ARM) -c $(BOB_SW)/cvqkd_security.c -o cvqkd_security_arm.o

cvqkd_bob_benchmark_pynq_arm.elf: bench_bob_arm.o cvqkd_security_arm.o
	$(CC_ARM) $(CFLAGS_ARM) bench_bob_arm.o cvqkd_security_arm.o $(LDFLAGS_ARM) -o cvqkd_bob_benchmark_pynq_arm.elf
	@echo ">>> Compilado cvqkd_bob_benchmark_pynq_arm.elf (Bob ARM Cortex-A9) con exito!"
	$(SIZE_ARM) $@

# ------------------------------------------------------------------------------
# EJECUCIÓN
# ------------------------------------------------------------------------------
run_bob_host: bench_bob_host
	./bench_bob_host

run_bob_arm: cvqkd_bob_benchmark_pynq_arm.elf
	python3 ../tools/run_board.py bench-bob

run_alice_arm: cvqkd_benchmark_pynq_arm.elf
	python3 ../tools/run_board.py bench-alice

clean:
	rm -f bench_host bench_arm.o cvqkd_benchmark_pynq_arm.elf \
	      bench_bob_host bench_bob_arm.o cvqkd_security_arm.o cvqkd_bob_benchmark_pynq_arm.elf

.PHONY: all host arm bob_host bob_arm run_bob_host run_bob_arm run_alice_arm clean
