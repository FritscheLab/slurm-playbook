#!/usr/bin/env bash
# Exercise the complete manifest-to-summary workflow without SLURM, using the
# same per-task worker and result validation as the batch pipeline.

# Fail on command errors and unset variables, including failures inside pipes.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/run_all_local.sh [--results-dir DIR] [--clean]

Runs every task in manifest order and then validates/combines the results.
Default output: results/local-all
EOF
}

# Resolve paths from this file so the wrapper works from any directory.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
RESULTS_DIR=${RESULTS_DIR:-"$PROJECT_ROOT/results/local-all"}
PYTHON_BIN=${PYTHON_BIN:-python3}
CLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --results-dir)
      [[ $# -ge 2 ]] || { printf 'ERROR: --results-dir requires a value\n' >&2; exit 64; }
      RESULTS_DIR=$2
      shift 2
      ;;
    --clean)
      CLEAN=1
      shift
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

prepare_args=(
  prepare
  --manifest "$PROJECT_ROOT/data/manifest.tsv"
  --results-dir "$RESULTS_DIR"
)
(( CLEAN )) && prepare_args+=(--clean)
# The guard verifies directory ownership before optional cleanup and prints a
# canonical path for every later stage to share.
RESULTS_DIR=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" "${prepare_args[@]}")
# A new run must not leave old aggregate files looking current. Individual task
# files are invalidated by run_local.sh immediately before each task executes.
RESULTS_DIR=$("$PYTHON_BIN" "$PROJECT_ROOT/analysis/pipeline_guard.py" invalidate \
  --manifest "$PROJECT_ROOT/data/manifest.tsv" \
  --results-dir "$RESULTS_DIR" \
  --aggregates)
# Source the shared setup so Python validation and thread limits affect this shell.
source "$SCRIPT_DIR/runtime_setup.sh"

# Read tasks in manifest order; `_` consumes columns this driver does not need.
while IFS=$'\t' read -r task_id _; do
  [[ $task_id == task_id ]] && continue
  RESULTS_DIR="$RESULTS_DIR" "$SCRIPT_DIR/run_local.sh" "$task_id"
done < "$PROJECT_ROOT/data/manifest.tsv"

# With `set -e`, aggregation is reached only if every local task succeeded.
"$PYTHON_BIN" "$PROJECT_ROOT/analysis/combine_results.py" \
  --manifest "$PROJECT_ROOT/data/manifest.tsv" \
  --input-dir "$RESULTS_DIR" \
  --output "$RESULTS_DIR/combined_results.csv" \
  --summary "$RESULTS_DIR/summary.md" \
  --run-label local-all

printf 'results_dir=%s\n' "$RESULTS_DIR"
