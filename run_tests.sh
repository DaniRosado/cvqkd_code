#!/usr/bin/env bash
# ==============================================================================
# Regresión del proyecto: testbenches RTL (Vivado Simulator) y test del módulo
# de seguridad de Bob (gcc).
#
# Uso:
#   ./run_tests.sh                 # todos los tests
#   ./run_tests.sh tb_sync_fifo    # solo los indicados
#   ./run_tests.sh --list          # lista de tests disponibles
#
# Necesita xvlog/xelab/xsim en el PATH, o la variable XILINX_VIVADO apuntando a
# la instalación de Vivado. Cada testbench imprime "RESULTADO: PASS" o
# "RESULTADO: FAIL"; los logs quedan en build/sim/<test>.log.
# ==============================================================================
set -u

ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD=${CVQKD_SIM_DIR:-$ROOT/build/sim}   # Directorio de trabajo (configurable)
DATA=$ROOT/cvqkd_matlab/data

A=$ROOT/cvqkd_alice/rtl
B=$ROOT/cvqkd_bob/rtl
M=$ROOT/cvqkd_mdr/rtl
IP=$ROOT/cvqkd_bob/ip

# RTL en orden de compilación (paquetes primero)
RTL_SV=(
    $A/bg1_rom_pkg.sv $M/mdr_rom_pkg.sv
    $A/L_RAM.sv $A/R_BRAM.sv $A/vnu_node.sv $A/cnu_serial_node.sv $A/barrel_shifter.sv
    $A/ldpc_controller_fsm.sv $A/ldpc_layer_datapath.sv $A/syndrome_checker.sv $A/ldpc_decoder_top.sv
    $M/mdr_alice_fsm.sv $M/mdr_alice_datapath.sv $M/mdr_alice_top.sv $A/alice_post_processing_core.sv
    $M/mdr_bob_datapath.sv $M/mdr_bob_streaming.sv
    $B/sync_fifo.sv $B/demux_framer.sv $B/phase_interpolator.sv $B/cvqkd_bob_dsp_top.sv $B/bob_stream_router.sv
    $B/mac_moments.sv $B/LLR_math_unit.sv $B/param_estimator_top.sv $B/mdr_accumulator.sv
    $B/barrel_shifter_384.sv $B/syndrome_calc_bg1.sv $B/cvqkd_syndrome_pingpong.sv $B/cvqkd_reconciliation_top.sv
    $B/cvqkd_bob_subsystem_top.sv
)
# Verilog: wrappers AXI y netlists de simulación de los cores de Xilinx
RTL_V=(
    $A/cvqkd_alice_axi_wrapper.v $B/cvqkd_bob_axi_wrapper.v
    $IP/cordic_vect_ip/cordic_vect_ip_sim_netlist.v $IP/cordic_rot_ip/cordic_rot_ip_sim_netlist.v
    $IP/cordic_sqrt_q16_16/cordic_sqrt_q16_16_sim_netlist.v $IP/div_gen_48_32_params/div_gen_48_32_params_sim_netlist.v
)

# Testbenches, de los unitarios a los de sistema completo
TESTS=(
    cvqkd_alice/sim/tb_barrel_shifter.sv
    cvqkd_alice/sim/tb_cnu_serial_node.sv
    cvqkd_alice/sim/tb_vnu_node.sv
    cvqkd_alice/sim/tb_ldpc_decoder_top.sv
    cvqkd_mdr/sim/tb_mdr_alice_top.sv
    cvqkd_alice/sim/tb_alice_post_processing_core.sv
    cvqkd_alice/sim/tb_cvqkd_alice_axi_wrapper.sv
    cvqkd_bob/sim/tb_sync_fifo.sv
    cvqkd_bob/sim/tb_barrel_shifter_384.sv
    cvqkd_bob/sim/tb_mac_moments.sv
    cvqkd_bob/sim/tb_LLR_Math_Unit.sv
    cvqkd_bob/sim/tb_param_estimator_top.sv
    cvqkd_bob/sim/tb_phase_interpolator.sv
    cvqkd_bob/sim/tb_cvqkd_bob_dsp_top.sv
    cvqkd_mdr/sim/tb_mdr_bob_streaming.sv
    cvqkd_bob/sim/tb_syndrome_calc_bg1.sv
    cvqkd_bob/sim/tb_cvqkd_syndrome_pingpong.sv
    cvqkd_bob/sim/tb_cvqkd_reconciliation_top.sv
    cvqkd_bob/sim/tb_cvqkd_bob_axi_wrapper.sv
    test_security
)

if [ "${1:-}" = "--list" ]; then
    for t in "${TESTS[@]}"; do basename "$t" .sv; done
    exit 0
fi

# Selección de tests
SELECTED=()
if [ $# -eq 0 ]; then
    SELECTED=("${TESTS[@]}")
else
    for name in "$@"; do
        found=""
        for t in "${TESTS[@]}"; do
            [ "$(basename "$t" .sv)" = "$name" ] && found=$t
        done
        [ -z "$found" ] && { echo "Test desconocido: $name (usa --list)" >&2; exit 1; }
        SELECTED+=("$found")
    done
fi

if ! command -v xvlog >/dev/null 2>&1; then
    if [ -n "${XILINX_VIVADO:-}" ]; then
        PATH=$XILINX_VIVADO/bin:$PATH
    else
        echo "No se encuentra xvlog: añade Vivado al PATH o define XILINX_VIVADO." >&2
        exit 1
    fi
fi
VIVADO_DIR=$(cd "$(dirname "$(command -v xvlog)")/.." && pwd)

mkdir -p "$BUILD"
cd "$BUILD" || exit 1
ln -sf "$DATA"/* .   # Los testbenches leen los vectores de MATLAB por nombre

# Compilación de la RTL (una sola vez)
need_rtl=0
for t in "${SELECTED[@]}"; do [ "$t" != test_security ] && need_rtl=1; done
if [ $need_rtl -eq 1 ]; then
    echo "Compilando RTL..."
    if ! xvlog -sv "${RTL_SV[@]}" > rtl_sv.log 2>&1 ||
       ! xvlog "${RTL_V[@]}" "$VIVADO_DIR/data/verilog/src/glbl.v" > rtl_v.log 2>&1; then
        grep -h ERROR rtl_sv.log rtl_v.log | head -5
        echo "Error compilando la RTL (ver $BUILD/rtl_*.log)"
        exit 1
    fi
fi

passed=0; failed=0
for t in "${SELECTED[@]}"; do
    name=$(basename "$t" .sv)
    log=$BUILD/$name.log
    start=$SECONDS
    printf '%-34s ' "$name"
    if [ "$t" = test_security ]; then
        gcc -O2 -Wall -Wextra -o test_security "$ROOT/cvqkd_bob/sw/test_security.c" \
            "$ROOT/cvqkd_bob/sw/cvqkd_security.c" -lm > "$log" 2>&1 && ./test_security >> "$log" 2>&1
    else
        xvlog -sv "$ROOT/$t" > "$log" 2>&1 &&
        xelab -L unisims_ver -L secureip --timescale 1ns/1ps -debug off \
              "work.$name" work.glbl -s "sim_$name" >> "$log" 2>&1 &&
        xsim "sim_$name" -R >> "$log" 2>&1
    fi
    if grep -aq "RESULTADO: PASS" "$log" && ! grep -aq "RESULTADO: FAIL" "$log"; then
        result=PASS; passed=$((passed + 1))
    else
        result=FAIL; failed=$((failed + 1))
    fi
    echo "$result ($((SECONDS - start)) s)"
done

echo "--------------------------------------------------"
echo "Tests: $((passed + failed))  PASS: $passed  FAIL: $failed   (logs en $BUILD)"
[ $failed -eq 0 ]
