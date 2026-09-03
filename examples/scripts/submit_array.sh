#!/usr/bin/env bash
# Submit all or selected manifest tasks as a bounded SLURM array.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/submit_array.sh [options]

Options:
  --tasks SPEC          task IDs/ranges for recovery, for example 6,11,19
  --results-dir DIR     result directory for a named run or recovery
  --max-concurrent N    maximum simultaneous array tasks (default: 8)
  --dry-run             validate and print the sbatch command
  -h, --help            show this help

Set SLURM_ACCOUNT and SLURM_PARTITION in the environment. PYTHON_BIN is
optional and defaults to python3. Value-taking options use a separate argument.
EOF
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
MANIFEST="$PROJECT_ROOT/data/manifest.tsv"
ACCOUNT=${SLURM_ACCOUNT:-}
PARTITION=${SLURM_PARTITION:-}
PYTHON_BIN=${PYTHON_BIN:-python3}
TASKS=
RESULTS_DIR_OVERRIDE=
MAX_CONCURRENT=8
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tasks)
      if [[ $# -lt 2 || -z ${2:-} || ${2:-} == -* ]]; then
        printf 'ERROR: --tasks requires a value\n' >&2
        exit 64
      fi
      TASKS=$2
      shift 2 ;;
    --results-dir)
      if [[ $# -lt 2 || -z ${2:-} || ${2:-} == -* ]]; then
        printf 'ERROR: --results-dir requires a value\n' >&2
        exit 64
      fi
      RESULTS_DIR_OVERRIDE=$2
      shift 2 ;;
    --max-concurrent)
      if [[ $# -lt 2 || -z ${2:-} || ${2:-} == -* ]]; then
        printf 'ERROR: --max-concurrent requires a value\n' >&2
        exit 64
      fi
      MAX_CONCURRENT=$2
      shift 2 ;;
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

[[ -n $ACCOUNT ]] || { printf 'ERROR: set SLURM_ACCOUNT in the environment\n' >&2; exit 64; }
[[ -n $PARTITION ]] || { printf 'ERROR: set SLURM_PARTITION in the environment\n' >&2; exit 64; }
[[ $MAX_CONCURRENT =~ ^[1-9][0-9]*$ ]] || {
  printf 'ERROR: --max-concurrent must be a positive integer\n' >&2
  exit 64
}
[[ -f $MANIFEST ]] || { printf 'ERROR: manifest not found: %s\n' "$MANIFEST" >&2; exit 66; }
source "$SCRIPT_DIR/runtime_setup.sh"

# Resolve caller-relative paths before sbatch changes into the project directory.
if [[ -n $RESULTS_DIR_OVERRIDE ]]; then
  RESULTS_DIR_OVERRIDE=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" resolve \
    --path "$RESULTS_DIR_OVERRIDE")
fi

# The guard derives the full task range from the manifest and validates recovery.
selection_args=(select --manifest "$MANIFEST")
[[ -n $TASKS ]] && selection_args+=(--tasks "$TASKS")
[[ -n $RESULTS_DIR_OVERRIDE ]] && selection_args+=(--results-dir "$RESULTS_DIR_OVERRIDE")
SELECTED_SPEC=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" \
  "${selection_args[@]}")
if ! [[ $SELECTED_SPEC =~ ^[1-9][0-9]*(-[1-9][0-9]*)?(,[1-9][0-9]*(-[1-9][0-9]*)?)*$ ]]; then
  printf 'ERROR: malformed task selection: %s\n' "$SELECTED_SPEC" >&2
  exit 70
fi
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
  printf '\nselected_tasks=%s\n' "$SELECTED_SPEC" >&2
  printf 'array_job=DRY_RUN results_dir=%s\n' "${RESULTS_DIR_OVERRIDE:-DRY_RUN}"
  exit 0
fi

command -v sbatch >/dev/null 2>&1 || {
  printf 'ERROR: sbatch is unavailable; use --dry-run or run on a login node\n' >&2
  exit 127
}
mkdir -p "$PROJECT_ROOT/logs" "$PROJECT_ROOT/results"

# Any named destination is prepared only after task/recovery validation succeeds.
if [[ -n $RESULTS_DIR_OVERRIDE ]]; then
  RESULTS_DIR_OVERRIDE=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" prepare \
    --manifest "$MANIFEST" --results-dir "$RESULTS_DIR_OVERRIDE")
  export RESULTS_DIR_OVERRIDE
fi

array_job=$("${command[@]}")
array_job=${array_job%%;*}  # Federated clusters may append ;CLUSTER.
[[ $array_job =~ ^[0-9]+$ ]] || {
  printf 'ERROR: unexpected sbatch --parsable response: %s\n' "$array_job" >&2
  exit 70
}

if [[ -n $RESULTS_DIR_OVERRIDE ]]; then
  results_dir=$RESULTS_DIR_OVERRIDE
else
  results_dir="$PROJECT_ROOT/results/$array_job"
  results_dir=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" prepare \
    --manifest "$MANIFEST" --results-dir "$results_dir")
fi

printf 'submitted array job %s for tasks %s; results: %s\n' \
  "$array_job" "$ARRAY_SPEC" "$results_dir" >&2
printf 'array_job=%s results_dir=%s\n' "$array_job" "$results_dir"
