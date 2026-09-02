#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/submit_array.sh [options]

Options:
  --account NAME          SLURM account (or set SLURM_ACCOUNT)
  --partition NAME        partition (or set SLURM_PARTITION)
  --max-concurrent N      simultaneous array tasks; default 8
  --tasks SPEC            IDs/ranges to recover, e.g. 6,11,19
  --results-dir DIR       existing owned run for partial recovery, or full-run output
  --python PATH           Python executable; default python3
  --dry-run               print the sbatch command without submitting
  -h, --help              show this help

On a real submission, stdout contains only the machine-readable array job ID.
Operational details are printed to stderr so this wrapper can be used safely in
command substitution.
EOF
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
MANIFEST="$PROJECT_ROOT/data/manifest.tsv"
ACCOUNT=${SLURM_ACCOUNT:-}
PARTITION=${SLURM_PARTITION:-}
MAX_CONCURRENT=8
TASKS=
RESULTS_DIR_OVERRIDE=
PYTHON_BIN=${PYTHON_BIN:-python3}
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account=*)
      ACCOUNT=${1#*=}
      [[ -n $ACCOUNT ]] || { printf 'ERROR: --account requires a value\n' >&2; exit 64; }
      shift
      ;;
    --account)
      [[ $# -ge 2 ]] || { printf 'ERROR: --account requires a value\n' >&2; exit 64; }
      ACCOUNT=$2; shift 2 ;;
    --partition=*)
      PARTITION=${1#*=}
      [[ -n $PARTITION ]] || { printf 'ERROR: --partition requires a value\n' >&2; exit 64; }
      shift
      ;;
    --partition)
      [[ $# -ge 2 ]] || { printf 'ERROR: --partition requires a value\n' >&2; exit 64; }
      PARTITION=$2; shift 2 ;;
    --max-concurrent=*)
      MAX_CONCURRENT=${1#*=}
      [[ -n $MAX_CONCURRENT ]] || { printf 'ERROR: --max-concurrent requires a value\n' >&2; exit 64; }
      shift
      ;;
    --max-concurrent)
      [[ $# -ge 2 ]] || { printf 'ERROR: --max-concurrent requires a value\n' >&2; exit 64; }
      MAX_CONCURRENT=$2; shift 2 ;;
    --tasks=*)
      TASKS=${1#*=}
      [[ -n $TASKS ]] || { printf 'ERROR: --tasks requires a value\n' >&2; exit 64; }
      shift
      ;;
    --tasks)
      [[ $# -ge 2 ]] || { printf 'ERROR: --tasks requires a value\n' >&2; exit 64; }
      TASKS=$2; shift 2 ;;
    --results-dir=*)
      RESULTS_DIR_OVERRIDE=${1#*=}
      [[ -n $RESULTS_DIR_OVERRIDE ]] || { printf 'ERROR: --results-dir requires a value\n' >&2; exit 64; }
      shift
      ;;
    --results-dir)
      [[ $# -ge 2 ]] || { printf 'ERROR: --results-dir requires a value\n' >&2; exit 64; }
      RESULTS_DIR_OVERRIDE=$2; shift 2 ;;
    --python=*)
      PYTHON_BIN=${1#*=}
      [[ -n $PYTHON_BIN ]] || { printf 'ERROR: --python requires a value\n' >&2; exit 64; }
      shift
      ;;
    --python)
      [[ $# -ge 2 ]] || { printf 'ERROR: --python requires a value\n' >&2; exit 64; }
      PYTHON_BIN=$2; shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      printf 'ERROR: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 64 ;;
  esac
done

[[ -n $ACCOUNT ]] || {
  printf 'ERROR: No SLURM account was supplied. Use --account or set SLURM_ACCOUNT.\n' >&2
  exit 64
}
[[ -n $PARTITION ]] || {
  printf 'ERROR: No partition was supplied. Use --partition or set SLURM_PARTITION.\n' >&2
  exit 64
}
[[ $MAX_CONCURRENT =~ ^[1-9][0-9]*$ ]] || {
  printf 'ERROR: --max-concurrent must be a positive integer\n' >&2
  exit 64
}
[[ -f $MANIFEST ]] || { printf 'ERROR: manifest not found: %s\n' "$MANIFEST" >&2; exit 66; }
source "$SCRIPT_DIR/runtime_setup.sh"

# Resolve user paths before any later cd. Relative paths therefore remain
# relative to the caller's working directory, not to this repository.
if [[ -n $RESULTS_DIR_OVERRIDE ]]; then
  RESULTS_DIR_OVERRIDE=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" resolve \
    --path "$RESULTS_DIR_OVERRIDE")
fi

selection_args=(select --manifest "$MANIFEST")
[[ -n $TASKS ]] && selection_args+=(--tasks "$TASKS")
[[ -n $RESULTS_DIR_OVERRIDE ]] && selection_args+=(--results-dir "$RESULTS_DIR_OVERRIDE")
selection=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" "${selection_args[@]}")
SELECTED_SPEC=${selection%%|*}
IS_PARTIAL=${selection##*|}
[[ $IS_PARTIAL == 0 || $IS_PARTIAL == 1 ]] || {
  printf 'ERROR: internal task-selection response was malformed: %s\n' "$selection" >&2
  exit 70
}
ARRAY_SPEC="${SELECTED_SPEC}%${MAX_CONCURRENT}"

export PROJECT_ROOT MANIFEST RESULTS_DIR_OVERRIDE PYTHON_BIN
command=(
  sbatch --parsable
  "--account=$ACCOUNT"
  "--partition=$PARTITION"
  "--array=$ARRAY_SPEC"
  "--chdir=$PROJECT_ROOT"
  "--output=$PROJECT_ROOT/logs/%x_%A_%a.out"
  "--error=$PROJECT_ROOT/logs/%x_%A_%a.err"
  --export=ALL
  "$PROJECT_ROOT/slurm/array.sbatch"
)

if (( DRY_RUN )); then
  printf 'DRY RUN:' >&2
  printf ' %q' "${command[@]}" >&2
  printf '\n' >&2
  printf 'DRY_RUN\n'
  exit 0
fi

command -v sbatch >/dev/null 2>&1 || {
  printf 'ERROR: sbatch is not available here. Use --dry-run locally or run this on a SLURM login node.\n' >&2
  exit 127
}
mkdir -p "$PROJECT_ROOT/logs" "$PROJECT_ROOT/results"
if [[ -n $RESULTS_DIR_OVERRIDE && $IS_PARTIAL == 0 ]]; then
  RESULTS_DIR_OVERRIDE=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" prepare \
    --manifest "$MANIFEST" \
    --results-dir "$RESULTS_DIR_OVERRIDE")
  export RESULTS_DIR_OVERRIDE
fi
array_job=$("${command[@]}")
array_job=${array_job%%;*}
[[ $array_job =~ ^[0-9]+$ ]] || {
  printf 'ERROR: unexpected sbatch --parsable response: %s\n' "$array_job" >&2
  exit 70
}

if [[ -n $RESULTS_DIR_OVERRIDE ]]; then
  expected_results=$RESULTS_DIR_OVERRIDE
else
  expected_results="$PROJECT_ROOT/results/$array_job"
  expected_results=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" prepare \
    --manifest "$MANIFEST" \
    --results-dir "$expected_results")
fi
printf 'submitted_array=%s spec=%s results=%s\n' \
  "$array_job" "$ARRAY_SPEC" "$expected_results" >&2
printf '%s\n' "$array_job"
