#!/usr/bin/env bash
#SBATCH --job-name=trait_single
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

# Run one manifest row as a standalone SLURM job. The small CPU, memory, and
# walltime requests are per job and should be retuned for real workloads.
# Separate stdout/stderr files use the job name (%x) and unique job ID (%j), so
# concurrent runs do not overwrite one another. Create logs/ before submission.

# Fail on errors, unset variables, or failed commands hidden inside pipelines.
set -Eeuo pipefail

# The submission directory anchors the project by default. Callers may override
# the manifest, task ID, or Python executable through the environment.
PROJECT_ROOT=${PROJECT_ROOT:-${SLURM_SUBMIT_DIR:?}}
MANIFEST=${MANIFEST:-"$PROJECT_ROOT/data/manifest.tsv"}
TASK_ID=${TASK_ID:-1}
PYTHON_BIN=${PYTHON_BIN:-python3}

cd "$PROJECT_ROOT"
source scripts/runtime_setup.sh

# Validate the manifest and initialize a pipeline-owned directory for this job.
RESULTS_DIR=$("$PYTHON_BIN" analysis/pipeline_guard.py prepare \
  --manifest "$MANIFEST" \
  --results-dir "$PROJECT_ROOT/results/${SLURM_JOB_ID:?}")

# Each task owns exactly one predictably named result file. The worker validates
# the selected row and publishes the completed CSV atomically.
printf -v OUTPUT '%s/task_%03d.csv' "$RESULTS_DIR" "$TASK_ID"
print_job_context
"$PYTHON_BIN" analysis/analyze_one_trait.py \
  --manifest "$MANIFEST" \
  --task-id "$TASK_ID" \
  --output "$OUTPUT"
