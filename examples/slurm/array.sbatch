#!/usr/bin/env bash
#SBATCH --job-name=trait_array
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=logs/%x_%A_%a.out
#SBATCH --error=logs/%x_%A_%a.err

# Run one manifest row per array element. These resource requests apply to each
# element, not to the array as a whole; tune them from measurements of real work.
# %A (array job) plus %a (element) keeps every element's stdout and stderr
# distinct. The submission wrapper creates logs/ and supplies the array range.

# Fail on errors, unset variables, or failed commands hidden inside pipelines.
set -Eeuo pipefail

# PROJECT_ROOT, MANIFEST, and PYTHON_BIN have useful submission-time defaults.
# SLURM must provide the element ID. A result override is used for recovery;
# otherwise all elements share a directory named for the base array job ID.
PROJECT_ROOT=${PROJECT_ROOT:-${SLURM_SUBMIT_DIR:?}}
MANIFEST=${MANIFEST:-"$PROJECT_ROOT/data/manifest.tsv"}
PYTHON_BIN=${PYTHON_BIN:-python3}
TASK_ID=${SLURM_ARRAY_TASK_ID:?SLURM_ARRAY_TASK_ID is required}
RESULTS_DIR=${RESULTS_DIR_OVERRIDE:-"$PROJECT_ROOT/results/${SLURM_ARRAY_JOB_ID:?}"}

cd "$PROJECT_ROOT"

# Concurrent elements safely validate/initialize the same pipeline-owned
# directory. Before any fallible environment setup, remove this task's older
# output and prior aggregates so a failed retry cannot masquerade as success.
RESULTS_DIR=$("$PYTHON_BIN" analysis/pipeline_guard.py prepare \
  --manifest "$MANIFEST" \
  --results-dir "$RESULTS_DIR")
RESULTS_DIR=$("$PYTHON_BIN" analysis/pipeline_guard.py invalidate \
  --manifest "$MANIFEST" \
  --results-dir "$RESULTS_DIR" \
  --task-id "$TASK_ID" \
  --aggregates)
source scripts/runtime_setup.sh

# Each element owns exactly one predictably named file. The worker validates its
# manifest row and publishes the completed CSV atomically.
printf -v OUTPUT '%s/task_%03d.csv' "$RESULTS_DIR" "$TASK_ID"
print_job_context
printf 'manifest=%s task_id=%s output=%s\n' "$MANIFEST" "$TASK_ID" "$OUTPUT"
"$PYTHON_BIN" analysis/analyze_one_trait.py \
  --manifest "$MANIFEST" \
  --task-id "$TASK_ID" \
  --output "$OUTPUT"
