#!/usr/bin/env bash
# Show an array as one compact row, then expand it to inspect each task.
set -Eeuo pipefail

[[ $# -eq 1 && $1 =~ ^[1-9][0-9]*$ ]] || {
  printf 'Usage: ./scripts/monitor.sh ARRAY_JOB_ID\n' >&2
  exit 64
}
ARRAY_JOB_ID=$1

command -v squeue >/dev/null 2>&1 || {
  printf 'ERROR: squeue is not available in this environment\n' >&2
  exit 127
}

printf '%s\n' '--- Compact array view ---'
squeue -j "$ARRAY_JOB_ID" -o '%.20i %.9P %.24j %.2t %.10M %.6D %R'

printf '\n%s\n' '--- One row per array element ---'
squeue -r -j "$ARRAY_JOB_ID" -o '%.20i %.2t %.10M %.16R %N'
