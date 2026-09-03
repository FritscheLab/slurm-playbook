#!/usr/bin/env bash
# Submit an array and one afterok combine job.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

# submit_array.sh is the single option parser and returns the run context here.
array_receipt=$("$SCRIPT_DIR/submit_array.sh" "$@")
case $array_receipt in
  array_job=*' results_dir='*) ;;
  Usage:*)
    # Keep option documentation centralized, changing only the wrapper name.
    printf 'Usage: ./scripts/submit_pipeline.sh%s\n' \
      "${array_receipt#Usage: ./scripts/submit_array.sh}"
    exit 0 ;;
  *)
    printf 'ERROR: malformed array receipt: %s\n' "$array_receipt" >&2
    exit 70 ;;
esac

array_job=${array_receipt#array_job=}
array_job=${array_job%% results_dir=*}
RESULTS_DIR=${array_receipt#* results_dir=}
if [[ -z $RESULTS_DIR ]]; then
  printf 'ERROR: array receipt has no results directory\n' >&2
  exit 70
fi
[[ $array_job == DRY_RUN || $array_job =~ ^[0-9]+$ ]] || {
  printf 'ERROR: malformed array receipt: %s\n' "$array_receipt" >&2
  exit 70
}

ACCOUNT=${SLURM_ACCOUNT:-}
PARTITION=${SLURM_PARTITION:-}
PYTHON_BIN=${PYTHON_BIN:-python3}
MANIFEST="$PROJECT_ROOT/data/manifest.tsv"
ARRAY_JOB_ID=$array_job
source "$SCRIPT_DIR/runtime_setup.sh"
export PROJECT_ROOT MANIFEST RESULTS_DIR ARRAY_JOB_ID PYTHON_BIN

# afterok prevents the fan-in stage from running after a failed array element.
combine_command=(
  sbatch --parsable
  "--account=$ACCOUNT"
  "--partition=$PARTITION"
  "--dependency=afterok:${array_job}"
  "--chdir=$PROJECT_ROOT"
  "--output=$PROJECT_ROOT/logs/%x_%j.out"
  "--error=$PROJECT_ROOT/logs/%x_%j.err"
  --export=ALL
  "$PROJECT_ROOT/slurm/combine.sbatch"
)

if [[ $array_job == DRY_RUN ]]; then
  printf 'DRY RUN:' >&2
  printf ' %q' "${combine_command[@]}" >&2
  printf '\n' >&2
  printf 'array_job=DRY_RUN combine_job=DRY_RUN results_dir=%s\n' "$RESULTS_DIR"
  exit 0
fi

combine_job=$("${combine_command[@]}")
combine_job=${combine_job%%;*}
[[ $combine_job =~ ^[0-9]+$ ]] || {
  printf 'ERROR: unexpected combine sbatch response: %s\n' "$combine_job" >&2
  exit 70
}

printf 'submitted combine job %s after array job %s\n' "$combine_job" "$array_job" >&2
printf 'array_job=%s combine_job=%s results_dir=%s\n' \
  "$array_job" "$combine_job" "$RESULTS_DIR"
