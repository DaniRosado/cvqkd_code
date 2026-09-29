# Makefile para Benchmark CV-QKD: Hardware FPGA vs CPU Software

CC_HOST = gcc
CC_ARM  = /home/drg/AMD/Xilin/2025.2/Vitis/gnu/aarch32/lin/gcc-arm-none-eabi/bin/arm-none-eabi-gcc

CFLAGS_HOST = -O3 -Wall -Wextra -I.
CFLAGS_ARM  = -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -O3 -Wall -Wextra -I. \
              -isystem /home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_platform/export/cvqkd_bob_platform/sw/standalone_ps7_cortexa9_0/include \
              -DPLATFORM_ARM_BAREMETAL=1

LDFLAGS_ARM = -specs=/home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_platform/export/cvqkd_bob_platform/sw/standalone_ps7_cortexa9_0/Xilinx.spec \
              -T /home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_app/src/lscript.ld \
              -L/home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_platform/export/cvqkd_bob_platform/sw/standalone_ps7_cortexa9_0/lib \
              -Wl,--start-group,-lxilstandalone,-lxiltimer,-lxil,-lgcc,-lc,--end-group

all: host arm

host: bench_host

bench_host: cvqkd_cpu_benchmark.c cvqkd_benchmark_data.h
	$(CC_HOST) $(CFLAGS_HOST) cvqkd_cpu_benchmark.c -o bench_host -lm
	@echo ">>> Compilado bench_host (x86-64) con exito!"

arm: cvqkd_benchmark_pynq_arm.elf

bench_arm.o: cvqkd_cpu_benchmark.c cvqkd_benchmark_data.h
	$(CC_ARM) $(CFLAGS_ARM) -c cvqkd_cpu_benchmark.c -o bench_arm.o

cvqkd_benchmark_pynq_arm.elf: bench_arm.o
	$(CC_ARM) $(CFLAGS_ARM) bench_arm.o $(LDFLAGS_ARM) -o cvqkd_benchmark_pynq_arm.elf
	@echo ">>> Compilado cvqkd_benchmark_pynq_arm.elf (ARM Cortex-A9) con exito!"

run_host: bench_host
	./bench_host

run_arm: cvqkd_benchmark_pynq_arm.elf
	./run_pynq_benchmark.py

clean:
	rm -f bench_host bench_arm.o cvqkd_benchmark_pynq_arm.elf

.PHONY: all host arm run_host run_arm clean
