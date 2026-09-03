#!/usr/bin/env bash
#SBATCH --job-name=trait_combine
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

# Fan in the array's per-task files into final tabular and human-readable
# outputs. The small resource envelope belongs to this combine job alone.
# Separate stdout/stderr files include the job name (%x) and job ID (%j), so
# repeated combines remain distinguishable. The wrapper creates logs/ first.

# Fail on errors, unset variables, or failed commands hidden inside pipelines.
set -Eeuo pipefail

# The project and manifest have submission-time defaults; the pipeline wrapper
# must export the exact result directory and upstream array ID. Python is
# replaceable for clusters whose default python3 is unsuitable.
PROJECT_ROOT=${PROJECT_ROOT:-${SLURM_SUBMIT_DIR:?}}
MANIFEST=${MANIFEST:-"$PROJECT_ROOT/data/manifest.tsv"}
RESULTS_DIR=${RESULTS_DIR:?RESULTS_DIR is required}
ARRAY_JOB_ID=${ARRAY_JOB_ID:?ARRAY_JOB_ID is required}
PYTHON_BIN=${PYTHON_BIN:-python3}

cd "$PROJECT_ROOT"
source scripts/runtime_setup.sh

# Revalidate that this is a pipeline-owned directory for the current manifest
# before reading any task output.
RESULTS_DIR=$("$PYTHON_BIN" analysis/pipeline_guard.py prepare \
  --manifest "$MANIFEST" \
  --results-dir "$RESULTS_DIR")
print_job_context
printf 'upstream_array=%s results_dir=%s\n' "$ARRAY_JOB_ID" "$RESULTS_DIR"

# submit_pipeline.sh attaches afterok:<array-job-id>, so this fan-in normally
# starts only after every array element succeeds. The combiner still verifies
# completeness and coherence before publishing both aggregate files.
"$PYTHON_BIN" analysis/combine_results.py \
  --manifest "$MANIFEST" \
  --input-dir "$RESULTS_DIR" \
  --output "$RESULTS_DIR/combined_results.csv" \
  --summary "$RESULTS_DIR/summary.md" \
  --run-label "slurm-array-${ARRAY_JOB_ID}"
