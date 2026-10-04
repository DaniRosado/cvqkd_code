#!/usr/bin/env bash
# ==============================================================================
# Curva waterfall de la reconciliación de Alice con la RTL real.
#
# Para cada distancia de fibra (es decir, cada SNR) y cada semilla, MATLAB genera
# una trama nueva (tb_generador_master.m con CVQKD_SOLO_ALICE=1) y el testbench
# del núcleo de Alice (tb_alice_post_processing_core) la reconcilia: MDR con K
# dinámico, LDPC (200 iteraciones como máximo) y comparación de la clave con la
# de Bob.
#
# Uso:
#   tools/waterfall_ldpc.sh                  # distancias y semillas por defecto
#   tools/waterfall_ldpc.sh -s 5 11 12 13    # 5 tramas en 11, 12 y 13 km
#
# Variables: XILINX_VIVADO (como run_tests.sh), MATLAB (ejecutable, por defecto
# "matlab") y CVQKD_JOBS (tramas en paralelo, por defecto 4).
# Resultados en build/waterfall: waterfall.csv (una fila por trama) y
# resumen.csv (una fila por distancia). Las tramas ya simuladas no se repiten.
# Duración orientativa: ~2 min por trama que converge y ~15-20 min por trama que
# agota las 200 iteraciones; el barrido por defecto tarda unas 3 horas con 5 en
# paralelo.
# ==============================================================================
set -u
export LC_ALL=C   # Punto decimal en sort, awk y seq

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/build/waterfall
MATLAB=${MATLAB:-matlab}
JOBS=${CVQKD_JOBS:-4}
SEEDS=10
if [ "${1:-}" = "-s" ]; then SEEDS=$2; shift 2; fi
DISTANCES=("$@")
[ ${#DISTANCES[@]} -eq 0 ] && DISTANCES=(8 10 11 11.5 12 12.5 13 13.5 14)

# 1. Compila el testbench y comprueba que pasa con los vectores de referencia
CVQKD_SIM_DIR=$OUT/sim "$ROOT/run_tests.sh" tb_alice_post_processing_core || exit 1
command -v xsim >/dev/null 2>&1 || PATH=$XILINX_VIVADO/bin:$PATH

# 2. Una trama: vectores de MATLAB y simulación. Deja una fila en resultado.csv:
#    distancia_km,semilla,snr_dim,convergido,iteraciones,columnas_distintas
run_point() {
    local L=$1 seed=$2 dir=$OUT/L${1}km_s$2
    [ -f "$dir/resultado.csv" ] && return
    mkdir -p "$dir" && cd "$dir" || return
    CVQKD_L_KM=$L CVQKD_SEED=$seed CVQKD_SOLO_ALICE=1 CVQKD_DATA_OUT=$dir \
        "$MATLAB" -batch "run('$ROOT/cvqkd_matlab/scripts/tb_generador_master.m')" > matlab.log 2>&1
    cp -r "$OUT/sim/xsim.dir" . && xsim sim_tb_alice_post_processing_core -R > tb.log 2>&1
    local snr conv iters cols
    snr=$(sed -n 's/.*SNR por dimension = //p' matlab.log)
    iters=$(grep -aoE '(en|las) [0-9]+ iteraciones' tb.log | grep -oE '[0-9]+')
    if grep -aq 'ha convergido' tb.log; then
        conv=1; cols=$(grep -aoE '[0-9]+/68' tb.log | cut -d/ -f1)
    else
        conv=0; cols=
    fi
    rm -rf xsim.dir ./*.txt ./*.hex
    [ -n "$snr" ] && [ -n "$iters" ] || { echo "Error en $dir (ver matlab.log y tb.log)" >&2; return; }
    echo "$L,$seed,$snr,$conv,$iters,$cols" > resultado.csv
    echo "  $L km, semilla $seed: SNR $snr, $([ $conv = 1 ] && echo "converge en $iters it., $cols/68 columnas distintas" || echo "no converge")"
}

echo "Barrido: ${DISTANCES[*]} km, $SEEDS tramas por distancia, $JOBS en paralelo"
for L in "${DISTANCES[@]}"; do
    for seed in $(seq 1 "$SEEDS"); do
        run_point "$L" "$seed" &
        while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
    done
done
wait

# 3. Resultados: todas las tramas simuladas y resumen por distancia
{
    echo "distancia_km,semilla,snr_dim,convergido,iteraciones,columnas_distintas"
    cat "$OUT"/L*km_s*/resultado.csv 2>/dev/null | sort -t, -k1,1g -k2,2n
} > "$OUT/waterfall.csv"

# Éxito: el LDPC converge y la clave coincide con la de Bob
{
    echo "distancia_km,snr_dim,tramas,exitos,tasa_exito,iteraciones_medias"
    awk -F, 'NR > 1 {
            n[$1]++; snr[$1] = $3
            if ($4 == 1 && $6 == 0) { ok[$1]++; it[$1] += $5 }
        }
        END {
            for (L in n) printf "%s,%s,%d,%d,%.3f,%s\n", L, snr[L], n[L], ok[L], ok[L] / n[L],
                                ok[L] ? sprintf("%.1f", it[L] / ok[L]) : ""
        }' "$OUT/waterfall.csv" | sort -t, -k1,1g
} > "$OUT/resumen.csv"

echo "--------------------------------------------------"
column -s, -t "$OUT/resumen.csv"
echo "(tramas en $OUT/waterfall.csv, resumen en $OUT/resumen.csv)"
