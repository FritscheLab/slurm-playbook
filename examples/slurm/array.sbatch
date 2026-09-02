#!/usr/bin/env bash
#SBATCH --job-name=trait_array
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=logs/%x_%A_%a.out
#SBATCH --error=logs/%x_%A_%a.err

set -Eeuo pipefail
PROJECT_ROOT=${PROJECT_ROOT:-${SLURM_SUBMIT_DIR:?}}
MANIFEST=${MANIFEST:-"$PROJECT_ROOT/data/manifest.tsv"}
PYTHON_BIN=${PYTHON_BIN:-python3}
TASK_ID=${SLURM_ARRAY_TASK_ID:?SLURM_ARRAY_TASK_ID is required}
RESULTS_DIR=${RESULTS_DIR_OVERRIDE:-"$PROJECT_ROOT/results/${SLURM_ARRAY_JOB_ID:?}"}

cd "$PROJECT_ROOT"
RESULTS_DIR=$("$PYTHON_BIN" analysis/pipeline_guard.py prepare \
  --manifest "$MANIFEST" \
  --results-dir "$RESULTS_DIR")
RESULTS_DIR=$("$PYTHON_BIN" analysis/pipeline_guard.py invalidate \
  --manifest "$MANIFEST" \
  --results-dir "$RESULTS_DIR" \
  --task-id "$TASK_ID" \
  --aggregates)
source scripts/runtime_setup.sh
printf -v OUTPUT '%s/task_%03d.csv' "$RESULTS_DIR" "$TASK_ID"
print_job_context
printf 'manifest=%s task_id=%s output=%s\n' "$MANIFEST" "$TASK_ID" "$OUTPUT"
"$PYTHON_BIN" analysis/analyze_one_trait.py \
  --manifest "$MANIFEST" \
  --task-id "$TASK_ID" \
  --output "$OUTPUT"
