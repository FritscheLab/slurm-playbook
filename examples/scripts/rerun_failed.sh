#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/rerun_failed.sh ARRAY_JOB_ID [--results-dir DIR] [--max-concurrent N]

Reads completed accounting data, prints failed terminal elements, and emits a
suggested recovery-pipeline command. The command reruns the selected elements
and schedules a replacement afterok combine job. Nothing is submitted
automatically: inspect each failed task's stderr and exit code first.
EOF
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
[[ $# -ge 1 ]] || { usage >&2; exit 64; }
ARRAY_JOB_ID=$1
shift
RESULTS_DIR="$PROJECT_ROOT/results/$ARRAY_JOB_ID"
MAX_CONCURRENT=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --results-dir) [[ $# -ge 2 ]] || exit 64; RESULTS_DIR=$2; shift 2 ;;
    --max-concurrent) [[ $# -ge 2 ]] || exit 64; MAX_CONCURRENT=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done

[[ $ARRAY_JOB_ID =~ ^[0-9]+$ ]] || { printf 'ERROR: invalid array job ID\n' >&2; exit 64; }
[[ $MAX_CONCURRENT =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: invalid concurrency\n' >&2; exit 64; }
command -v sacct >/dev/null 2>&1 || { printf 'ERROR: sacct is not available\n' >&2; exit 127; }

accounting=$(sacct -nX -P -j "$ARRAY_JOB_ID" -o JobIDRaw,State,ExitCode)
failed_rows=$(printf '%s\n' "$accounting" | awk -F'|' -v id="$ARRAY_JOB_ID" '
  $1 ~ ("^" id "_[0-9]+$") {
    state=$2
    sub(/^[[:space:]]+/, "", state)
    sub(/[[:space:]+].*$/, "", state)
    if (state ~ /^(FAILED|OUT_OF_MEMORY|TIMEOUT|CANCELLED|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE|REVOKED)$/) {
      print $1 "|" state "|" $3
    }
  }
')

if [[ -z $failed_rows ]]; then
  printf 'No failed terminal array elements found for %s.\n' "$ARRAY_JOB_ID"
  exit 0
fi

printf '%s\n' 'Failed elements (diagnose these logs before resubmitting):'
printf '%s\n' "$failed_rows"
failed_ids=$(printf '%s\n' "$failed_rows" \
  | awk -F'[|_]' '{print $2}' \
  | sort -n -u \
  | paste -sd, -)

printf '\nSuggested command after the root cause is corrected:\n'
printf 'Replace YOUR_ACCOUNT and YOUR_PARTITION with the values for this run.\n'
printf 'SLURM_ACCOUNT=YOUR_ACCOUNT SLURM_PARTITION=YOUR_PARTITION %q --tasks %q --max-concurrent %q --results-dir %q\n' \
  "$SCRIPT_DIR/submit_pipeline.sh" "$failed_ids" "$MAX_CONCURRENT" "$RESULTS_DIR"
