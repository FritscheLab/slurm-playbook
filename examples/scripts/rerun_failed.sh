#!/usr/bin/env bash
# Diagnose failed array elements and suggest—but never submit—a recovery.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
[[ $# -ge 1 && $# -le 2 && $1 =~ ^[1-9][0-9]*$ ]] || {
  printf 'Usage: ./scripts/rerun_failed.sh ARRAY_JOB_ID [RESULTS_DIR]\n' >&2
  exit 64
}
ARRAY_JOB_ID=$1
RESULTS_DIR=${2:-"$PROJECT_ROOT/results/$ARRAY_JOB_ID"}
MAX_CONCURRENT=${MAX_CONCURRENT:-8}

[[ -n $RESULTS_DIR ]] || {
  printf 'ERROR: RESULTS_DIR must not be empty\n' >&2
  exit 64
}
[[ $MAX_CONCURRENT =~ ^[1-9][0-9]*$ ]] || {
  printf 'ERROR: MAX_CONCURRENT must be a positive integer\n' >&2
  exit 64
}
command -v sacct >/dev/null 2>&1 || {
  printf 'ERROR: sacct is not available in this environment\n' >&2
  exit 127
}
# -X omits job steps; awk keeps only individual elements of this array.
failed_rows=$(sacct -nX -P -j "$ARRAY_JOB_ID" \
  --state=FAILED,OUT_OF_MEMORY,TIMEOUT,CANCELLED,NODE_FAIL,PREEMPTED,BOOT_FAIL,DEADLINE,REVOKED \
  --format=JobIDRaw,State,ExitCode \
  | awk -F'|' -v id="$ARRAY_JOB_ID" '$1 ~ ("^" id "_[0-9]+$")')

if [[ -z $failed_rows ]]; then
  printf 'No failed terminal array elements found for %s.\n' "$ARRAY_JOB_ID"
  exit 0
fi

printf '%s\n' 'Failed elements (inspect their logs before resubmitting):'
printf '%s\n%s\n' 'JobIDRaw|State|ExitCode' "$failed_rows"

# Convert IDs such as 12345_7 into the sorted task specification 2,7,11.
failed_ids=$(printf '%s\n' "$failed_rows" \
  | awk -F'[|_]' '{print $2}' \
  | sort -n -u \
  | paste -sd, -)

printf '\nAfter correcting the root cause, review and run:\n'
printf '%q --tasks %q --results-dir %q --max-concurrent %q\n' \
  './scripts/submit_pipeline.sh' "$failed_ids" "$RESULTS_DIR" "$MAX_CONCURRENT"
printf 'SLURM_ACCOUNT and SLURM_PARTITION are read from your environment.\n'
