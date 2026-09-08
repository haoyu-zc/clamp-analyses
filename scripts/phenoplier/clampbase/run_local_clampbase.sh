#!/usr/bin/env bash
# Worklist runner for CLAMPbase coverage models on a NO-CGROUP host (local, lab).
# For each rs:seed: atomically stream the RDS from pico, take a per-model flock,
# then run the hardened per-model helper with a single-threaded BLAS strategy
# (OMP=1 globally so step3's 22 parallel chromosomes don't thrash; step7 uses
# many single-threaded workers). Runs CONC models at a time. Idempotent + resume-safe.
#
# Env overrides (defaults = local box):
#   PHENOPLIER_ENVBIN   conda env bin on PATH
#   PHENOPLIER_HOME     workspace root
#   CLAMPBASE_CENTRAL   results collection (stores/ + summaries/)
#   CLAMPBASE_MODELS    local RDS staging dir
#   CLAMP_SRC_SSH       host holding the source RDS (pico)
#   CLAMPBASE_WORKLIST  space-separated rs:seed pairs
#   CONC                concurrent models (default 2)
set -o pipefail   # not -e: one failed model must not kill the pool; not -u: empty assoc-array count trips old bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENVBIN="${PHENOPLIER_ENVBIN:-/home/haoyu/miniforge3/envs/phenoplier-cli-neo/bin}"
export PATH="$ENVBIN:$PATH"
export PHENOPLIER_HOME="${PHENOPLIER_HOME:-/media/data/phenoplier_workspace}"
export PHENOPLIER_ROOT_DIR="$PHENOPLIER_HOME"
export CLAMPBASE_CENTRAL="${CLAMPBASE_CENTRAL:-/media/data/clampbase_coverage}"
MODELS="${CLAMPBASE_MODELS:-/media/data/clampbase_models}"
SRC_SSH="${CLAMP_SRC_SSH:-pico}"
SRC_ROOT=/pividori_lab/marc_projects/clamp-analyses-coverage-bp/output/01_model_building/02_archs4/02_coverage_study
CONC="${CONC:-2}"
LOGS="$CLAMPBASE_CENTRAL/logs"; mkdir -p "$MODELS" "$LOGS" "$CLAMPBASE_CENTRAL/stores" "$CLAMPBASE_CENTRAL/summaries"

# No-cgroup BLAS strategy (see plan / Codex review): single-threaded everything.
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1
export CLAMPBASE_NW_STEP6=1 CLAMPBASE_BLAS_STEP6=1
export CLAMPBASE_NW_STEP7="${CLAMPBASE_NW_STEP7:-12}" CLAMPBASE_BLAS_STEP7=1
export CLAMPBASE_NJOBS="${CLAMPBASE_NJOBS:-22}"

# fraction -> coverage-study level dir
lvl_for() { case "$1" in
  1) echo 00_bp_coverage_study_01;; 5) echo 01_bp_coverage_study_05;;
  10) echo 02_bp_coverage_study_10;; 25) echo 03_bp_coverage_study_25;;
  50) echo 04_bp_coverage_study_50;; 75) echo 05_bp_coverage_study_75;;
  100) echo 06_bp_coverage_study_100;; *) echo "?";; esac; }

# local's share, heaviest (deepest tail) first
WORKLIST=(${CLAMPBASE_WORKLIST:-100:1 100:2 100:3 25:2 25:3})

run_one() {
  local rs="$1" seed="$2"
  local name="cov_rs${rs}_seed${seed}_CLAMPbase"
  local log="$LOGS/${name}.log"
  {
    echo "===== $name  $(date -Is) ====="
    # single-flight per model
    exec 9>"$MODELS/.lock.${name}"
    if ! flock -n 9; then echo "[skip] $name already locked by another worker"; return 0; fi
    local rds="$MODELS/${name}.rds"
    local src="$SRC_ROOT/$(lvl_for "$rs")/study_coverage_rs${rs}_seed_${seed}/CLAMPbase.rds"
    # Atomic RDS stream: .partial -> byte-count check vs source -> rename.
    if [ ! -s "$rds" ]; then
      local want have
      want=$(ssh "$SRC_SSH" "stat -c%s '$src'" 2>/dev/null | tr -dc 0-9)
      echo "[stream] $src ($want B) -> $rds"
      ssh "$SRC_SSH" "cat '$src'" > "$rds.partial" 2>/dev/null
      have=$(stat -c%s "$rds.partial" 2>/dev/null | tr -dc 0-9)
      if [ -n "$want" ] && [ "$want" = "$have" ]; then mv -f "$rds.partial" "$rds"; else
        echo "[ERROR] $name: RDS stream size mismatch want=$want have=$have"; rm -f "$rds.partial"; return 1; fi
    fi
    bash "$HERE/_run_clampbase_model.sh" "$name" "$rds"
  } >> "$log" 2>&1
}

echo "[worklist ${CONC}-wide] ${#WORKLIST[@]} models on $(hostname) $(date -Is)"
declare -A pids
idx=0
while (( idx < ${#WORKLIST[@]} )) || (( ${#pids[@]} > 0 )); do
  while (( ${#pids[@]} < CONC )) && (( idx < ${#WORKLIST[@]} )); do
    p="${WORKLIST[$idx]}"; idx=$((idx+1))
    echo "[launch] rs${p%%:*} seed${p##*:}  $(date -Is)"
    run_one "${p%%:*}" "${p##*:}" &
    pids[$!]=1
  done
  wait -n 2>/dev/null || true
  for pid in "${!pids[@]}"; do kill -0 "$pid" 2>/dev/null || unset 'pids[$pid]'; done
done
echo "[all-done] $(hostname) $(date -Is)"
