#!/bin/bash
#SBATCH -J cb_a_cov
#SBATCH -p acpu
#SBATCH --account=amc-general
#SBATCH --qos=cpu-long
#SBATCH -c 16
#SBATCH --mem=56G
#SBATCH --time=48:00:00
#SBATCH -o /pl/active/pivlab/projects/hzhang/clampbase_coverage/logs/%x_%A_%a.out
#
# Alpine SPECULATIVE hedge: rs50 x3 CLAMPbase coverage. Pico's baseline is the
# guaranteed fallback -- if acpu congestion keeps these pending, no loss.
# RDS must be pre-staged (pico->local->alpine) to $BASE/models/. Submit:
#   sbatch --array=0-2%3 alpine_clampbase.sbatch
set -uo pipefail
RS=(50 50 50); SEED=(1 2 3)
i="${SLURM_ARRAY_TASK_ID:?run as --array=0-2%3}"
rs="${RS[$i]}"; seed="${SEED[$i]}"

MF=/pl/active/pivlab/projects/hzhang/miniforge3
PREFIX=/projects/hzhang24@xsede.org/software/anaconda/envs/phenoplier-cli-neo
BASE=/pl/active/pivlab/projects/hzhang/clampbase_coverage
source "$MF/etc/profile.d/conda.sh" 2>/dev/null || true
conda activate "$PREFIX" 2>/dev/null || true
export PATH="$PREFIX/bin:$PATH"
export PHENOPLIER_HOME=/pl/active/pivlab/projects/hzhang/phenoplier_workspace
export CLAMPBASE_CENTRAL="$BASE"
mkdir -p "$BASE/logs" "$BASE/models"

name="cov_rs${rs}_seed${seed}_CLAMPbase"
rds="$BASE/models/${name}.rds"
[ -s "$rds" ] || { echo "[ERROR] $name: staged RDS missing at $rds (stage pico->local->alpine first)"; exit 1; }
# SLURM cgroup confines pools; keep serial step6 + capped step7 (defaults in helper).
bash /pl/active/pivlab/projects/hzhang/clampbase_scripts/_run_clampbase_model.sh "$name" "$rds"
