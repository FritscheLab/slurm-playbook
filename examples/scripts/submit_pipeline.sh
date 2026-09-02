#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/submit_pipeline.sh [options]

Submits a manifest array and a combine job with afterok dependency.

Options are the same as submit_array.sh:
  --account NAME | --partition NAME | --max-concurrent N
  --tasks SPEC | --results-dir DIR | --python PATH | --dry-run
EOF
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
ACCOUNT=${SLURM_ACCOUNT:-}
PARTITION=${SLURM_PARTITION:-}
MAX_CONCURRENT=8
TASKS=
RESULTS_DIR_OVERRIDE=
PYTHON_BIN=${PYTHON_BIN:-python3}
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account=*) ACCOUNT=${1#*=}; [[ -n $ACCOUNT ]] || { printf 'ERROR: --account requires a value\n' >&2; exit 64; }; shift ;;
    --account) [[ $# -ge 2 ]] || exit 64; ACCOUNT=$2; shift 2 ;;
    --partition=*) PARTITION=${1#*=}; [[ -n $PARTITION ]] || { printf 'ERROR: --partition requires a value\n' >&2; exit 64; }; shift ;;
    --partition) [[ $# -ge 2 ]] || exit 64; PARTITION=$2; shift 2 ;;
    --max-concurrent=*) MAX_CONCURRENT=${1#*=}; [[ -n $MAX_CONCURRENT ]] || { printf 'ERROR: --max-concurrent requires a value\n' >&2; exit 64; }; shift ;;
    --max-concurrent) [[ $# -ge 2 ]] || exit 64; MAX_CONCURRENT=$2; shift 2 ;;
    --tasks=*) TASKS=${1#*=}; [[ -n $TASKS ]] || { printf 'ERROR: --tasks requires a value\n' >&2; exit 64; }; shift ;;
    --tasks) [[ $# -ge 2 ]] || exit 64; TASKS=$2; shift 2 ;;
    --results-dir=*) RESULTS_DIR_OVERRIDE=${1#*=}; [[ -n $RESULTS_DIR_OVERRIDE ]] || { printf 'ERROR: --results-dir requires a value\n' >&2; exit 64; }; shift ;;
    --results-dir) [[ $# -ge 2 ]] || exit 64; RESULTS_DIR_OVERRIDE=$2; shift 2 ;;
    --python=*) PYTHON_BIN=${1#*=}; [[ -n $PYTHON_BIN ]] || { printf 'ERROR: --python requires a value\n' >&2; exit 64; }; shift ;;
    --python) [[ $# -ge 2 ]] || exit 64; PYTHON_BIN=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
done

[[ -n $ACCOUNT ]] || { printf 'ERROR: No SLURM account was supplied. Use --account or set SLURM_ACCOUNT.\n' >&2; exit 64; }
[[ -n $PARTITION ]] || { printf 'ERROR: No partition was supplied. Use --partition or set SLURM_PARTITION.\n' >&2; exit 64; }
source "$SCRIPT_DIR/runtime_setup.sh"
if [[ -n $RESULTS_DIR_OVERRIDE ]]; then
  RESULTS_DIR_OVERRIDE=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" resolve \
    --path "$RESULTS_DIR_OVERRIDE")
fi

array_args=(--account "$ACCOUNT" --partition "$PARTITION" --max-concurrent "$MAX_CONCURRENT" --python "$PYTHON_BIN")
[[ -n $TASKS ]] && array_args+=(--tasks "$TASKS")
[[ -n $RESULTS_DIR_OVERRIDE ]] && array_args+=(--results-dir "$RESULTS_DIR_OVERRIDE")
(( DRY_RUN )) && array_args+=(--dry-run)

if (( DRY_RUN )); then
  "$SCRIPT_DIR/submit_array.sh" "${array_args[@]}" >/dev/null
  printf 'DRY RUN: sbatch --parsable --account=%q --partition=%q ' "$ACCOUNT" "$PARTITION" >&2
  printf '%q %q %q %q %q\n' \
    '--dependency=afterok:<array_job_id>' \
    "--chdir=$PROJECT_ROOT" \
    "--output=$PROJECT_ROOT/logs/%x_%j.out" \
    "--error=$PROJECT_ROOT/logs/%x_%j.err" \
    "$PROJECT_ROOT/slurm/combine.sbatch" >&2
  printf 'array_job=DRY_RUN combine_job=DRY_RUN results_dir=%s\n' \
    "${RESULTS_DIR_OVERRIDE:-DRY_RUN}"
  exit 0
fi

array_job=$("$SCRIPT_DIR/submit_array.sh" "${array_args[@]}")
if [[ -n $RESULTS_DIR_OVERRIDE ]]; then
  RESULTS_DIR=$RESULTS_DIR_OVERRIDE
else
  RESULTS_DIR="$PROJECT_ROOT/results/$array_job"
fi
MANIFEST="$PROJECT_ROOT/data/manifest.tsv"
ARRAY_JOB_ID=$array_job
export PROJECT_ROOT MANIFEST RESULTS_DIR ARRAY_JOB_ID PYTHON_BIN

command -v sbatch >/dev/null 2>&1 || {
  printf 'ERROR: sbatch is not available here. Run this on a SLURM login node.\n' >&2
  exit 127
}
combine_job=$(sbatch --parsable \
  "--account=$ACCOUNT" \
  "--partition=$PARTITION" \
  "--dependency=afterok:${array_job}" \
  "--chdir=$PROJECT_ROOT" \
  "--output=$PROJECT_ROOT/logs/%x_%j.out" \
  "--error=$PROJECT_ROOT/logs/%x_%j.err" \
  --export=ALL \
  "$PROJECT_ROOT/slurm/combine.sbatch")
combine_job=${combine_job%%;*}
[[ $combine_job =~ ^[0-9]+$ ]] || {
  printf 'ERROR: unexpected combine sbatch response: %s\n' "$combine_job" >&2
  exit 70
}

printf 'array_job=%s combine_job=%s results_dir=%s\n' \
  "$array_job" "$combine_job" "$RESULTS_DIR"
