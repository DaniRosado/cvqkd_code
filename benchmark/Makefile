# Makefile para Benchmarks CV-QKD (Alice y Bob): Hardware FPGA vs CPU Software

CC_HOST = gcc
CC_ARM  = /home/drg/AMD/Xilin/2025.2/Vitis/gnu/aarch32/lin/gcc-arm-none-eabi/bin/arm-none-eabi-gcc
SIZE_ARM = /home/drg/AMD/Xilin/2025.2/Vitis/gnu/aarch32/lin/gcc-arm-none-eabi/bin/arm-none-eabi-size

CFLAGS_HOST = -O3 -Wall -Wextra -I.
CFLAGS_ARM  = -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -O3 -Wall -Wextra -I. \
              -isystem /home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_platform/export/cvqkd_bob_platform/sw/standalone_ps7_cortexa9_0/include \
              -DPLATFORM_ARM_BAREMETAL=1

LDFLAGS_ARM = -specs=/home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_platform/export/cvqkd_bob_platform/sw/standalone_ps7_cortexa9_0/Xilinx.spec \
              -T /home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_app/src/lscript.ld \
              -L/home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_platform/export/cvqkd_bob_platform/sw/standalone_ps7_cortexa9_0/lib \
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

bench_bob_host: cvqkd_bob_cpu_benchmark.c cvqkd_security.c cvqkd_security.h matlab_vectors.h cvqkd_benchmark_data.h
	$(CC_HOST) $(CFLAGS_HOST) cvqkd_bob_cpu_benchmark.c cvqkd_security.c -o bench_bob_host -lm
	@echo ">>> Compilado bench_bob_host (Bob x86-64) con exito!"

bob_arm: cvqkd_bob_benchmark_pynq_arm.elf

bench_bob_arm.o: cvqkd_bob_cpu_benchmark.c cvqkd_security.h matlab_vectors.h cvqkd_benchmark_data.h
	$(CC_ARM) $(CFLAGS_ARM) -c cvqkd_bob_cpu_benchmark.c -o bench_bob_arm.o

cvqkd_security_arm.o: cvqkd_security.c cvqkd_security.h
	$(CC_ARM) $(CFLAGS_ARM) -c cvqkd_security.c -o cvqkd_security_arm.o

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
	python3 run_bob_benchmark_arm.py

clean:
	rm -f bench_host bench_arm.o cvqkd_benchmark_pynq_arm.elf \
	      bench_bob_host bench_bob_arm.o cvqkd_security_arm.o cvqkd_bob_benchmark_pynq_arm.elf

.PHONY: all host arm bob_host bob_arm run_bob_host run_bob_arm clean
