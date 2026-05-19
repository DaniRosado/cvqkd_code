# AGENTS.md — CV-QKD Hardware (GG02)

## Project

SystemVerilog hardware (FPGA-synthesizable) for Continuous-Variable QKD.  
DSP receiver (Bob) + LDPC decoder (Alice) + 8D Multidimensional Reconciliation (MDR)  
+ MATLAB Golden Model that generates test vectors.

## Repo layout

| Directory | Role |
|---|---|
| `cvqkd_matlab/scripts/` | Channel simulation, test vector generation (`tb_generador_master.m`) |
| `cvqkd_matlab/data/` | `.txt` test vectors consumed by all SV testbenches |
| `cvqkd_bob/rtl/` | Bob DSP: demux, phase estimation, CORDIC, LLR math, syndrome calc |
| `cvqkd_alice/rtl/` | LDPC decoder: Layered Min-Sum, Z=384, 5G BG1 (46×68 base) |
| `cvqkd_mdr/rtl/` | 8D reconciliation: normalization, rotation, BPSK mapping |

## Toolchain

Only `cvqkd_alice/` has a Makefile (Xilinx Vivado + optional Verilator).

```makefile
# Vivado flow (default)
make tb_system          # Full LDPC system testbench
make tb_vnu             # VNU unit test
make tb_cnu             # CNU unit test  
make tb_shifter         # Barrel shifter unit test
make lint               # Verilator lint-only (no sim)
make tb_system_v        # Verilator simulation (open-source)
make clean

# Override Vivado path
make XILINX_VIVADO="C:/Xilinx/Vivado/2024.1" tb_system
```

**Both Bob DSP and MDR have no Makefile** — run their testbenches manually via Vivado/Questa/Verilator.

Vivado requirement: Xilinx CORDIC IP cores are used in Bob DSP but **not shipped** in the repo — configure in Vivado block design or use `CORDIC` IP from IP catalog.

## Simulation flow

1. **MATLAB**: Run `cvqkd_matlab/scripts/tb_generador_master.m` → writes `.txt` files to `cvqkd_matlab/data/`
2. **RTL**: Testbenches read those `.txt` files (absolute paths or relative fallbacks: `./`, `sim/`, `data/`)
3. **Check**: testbenches compare RTL output against MATLAB references at runtime (no waveform inspection needed)

## LDPC decoder quirks

- **Non-zero target syndrome**: CV-QKD Bob defines the syndrome; Alice must match it. Early termination checks `row_syndrome == 0`, not syndrome == 0.
- **Scaled Min-Sum**: `norm_mag = raw_mag - (raw_mag >> 2)` (alpha=0.75).
- **FSM**: `ST_IDLE → ST_LOAD → ST_READ_LAYER → ST_WRITE_LAYER → ST_CHECK → ST_DONE`. Includes `ST_READ_DRAIN` for pipeline alignment.
- **BRAM latency**: 1-cycle read latency. Control signals (valid, we, addr) propagate through `_q` / `_prev` registers to stay aligned.

## Endianness trap

Testbenches and RTL disagree on bit ordering. When loading/storing, watch for `Z-1-i` index reversals vs raw `[i]`. Key reference lines:

```
tb_ldpc_top_system.sv:  exp0 = ram_key_ref[c][Z-1-((i + int'(s)) % Z)];
```

If RTL output doesn't match, the first debugging step is to check/reverse bit index direction.

## Sync-conflict files in data/

`cvqkd_matlab/data/` contains `.sync-conflict-*` files from Syncthing. These may cause stale reference mismatches — delete or ignore them when regenerating golden data.

## Key parameters

- Z = 384 (submatrix size), W = 16 (LLR bit width), MAX_ITER = 20
- ADC_WIDTH = 16, DSP_WIDTH = 18
- N_BLOCKS = 3264, N_SYMBOLS = 13056 (MDR)
- BG_ROM[46][68], shift values in `bg_rom_pkg.sv`

## Conventions

- Pipeline stages: suffix `_q` for delayed/flopped signals
- Separate FSM states for load / read / write — never mix phases
- Aim for synthesizable code: no latches, no combo loops
- `-d SIMULATION` compile flag to enable sim-only code
