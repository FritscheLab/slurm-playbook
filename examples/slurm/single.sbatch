#!/usr/bin/env bash
#SBATCH --job-name=trait_single
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -Eeuo pipefail
PROJECT_ROOT=${PROJECT_ROOT:-${SLURM_SUBMIT_DIR:?}}
MANIFEST=${MANIFEST:-"$PROJECT_ROOT/data/manifest.tsv"}
TASK_ID=${TASK_ID:-1}
PYTHON_BIN=${PYTHON_BIN:-python3}
cd "$PROJECT_ROOT"
source scripts/runtime_setup.sh
RESULTS_DIR=$("$PYTHON_BIN" analysis/pipeline_guard.py prepare \
  --manifest "$MANIFEST" \
  --results-dir "$PROJECT_ROOT/results/${SLURM_JOB_ID:?}")
printf -v OUTPUT '%s/task_%03d.csv' "$RESULTS_DIR" "$TASK_ID"
print_job_context
"$PYTHON_BIN" analysis/analyze_one_trait.py \
  --manifest "$MANIFEST" \
  --task-id "$TASK_ID" \
  --output "$OUTPUT"
