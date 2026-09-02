#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/run_local.sh TASK_ID [--results-dir DIR]

Runs exactly one manifest row without SLURM. By default, writes to
results/local/task_NNN.csv. RESULTS_DIR may also be supplied as an environment
variable.
EOF
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
PYTHON_BIN=${PYTHON_BIN:-python3}

[[ $# -ge 1 ]] || { usage >&2; exit 64; }
TASK_ID=$1
shift
RESULTS_DIR=${RESULTS_DIR:-"$PROJECT_ROOT/results/local"}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --results-dir)
      [[ $# -ge 2 ]] || { printf 'ERROR: --results-dir requires a value\n' >&2; exit 64; }
      RESULTS_DIR=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

[[ $TASK_ID =~ ^[1-9][0-9]*$ ]] || {
  printf 'ERROR: TASK_ID must be a positive integer\n' >&2
  exit 64
}

RESULTS_DIR=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" prepare \
  --manifest "$PROJECT_ROOT/data/manifest.tsv" \
  --results-dir "$RESULTS_DIR")
RESULTS_DIR=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" invalidate \
  --manifest "$PROJECT_ROOT/data/manifest.tsv" \
  --results-dir "$RESULTS_DIR" \
  --task-id "$TASK_ID" \
  --aggregates)
source "$SCRIPT_DIR/runtime_setup.sh"
cd "$PROJECT_ROOT"
print_job_context
printf -v OUTPUT '%s/task_%03d.csv' "$RESULTS_DIR" "$TASK_ID"
"$PYTHON_BIN" analysis/analyze_one_trait.py \
  --manifest data/manifest.tsv \
  --task-id "$TASK_ID" \
  --output "$OUTPUT"
