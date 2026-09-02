#!/usr/bin/env bash
#SBATCH --job-name=trait_combine
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -Eeuo pipefail
PROJECT_ROOT=${PROJECT_ROOT:-${SLURM_SUBMIT_DIR:?}}
MANIFEST=${MANIFEST:-"$PROJECT_ROOT/data/manifest.tsv"}
RESULTS_DIR=${RESULTS_DIR:?RESULTS_DIR is required}
ARRAY_JOB_ID=${ARRAY_JOB_ID:?ARRAY_JOB_ID is required}
PYTHON_BIN=${PYTHON_BIN:-python3}

cd "$PROJECT_ROOT"
source scripts/runtime_setup.sh
RESULTS_DIR=$("$PYTHON_BIN" analysis/pipeline_guard.py prepare \
  --manifest "$MANIFEST" \
  --results-dir "$RESULTS_DIR")
print_job_context
printf 'upstream_array=%s results_dir=%s\n' "$ARRAY_JOB_ID" "$RESULTS_DIR"
"$PYTHON_BIN" analysis/combine_results.py \
  --manifest "$MANIFEST" \
  --input-dir "$RESULTS_DIR" \
  --output "$RESULTS_DIR/combined_results.csv" \
  --summary "$RESULTS_DIR/summary.md" \
  --run-label "slurm-array-${ARRAY_JOB_ID}"
