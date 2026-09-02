#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -eq 1 && $1 =~ ^[0-9]+$ ]] || {
  printf 'Usage: ./scripts/monitor.sh ARRAY_JOB_ID\n' >&2
  exit 64
}
ARRAY_JOB_ID=$1

command -v squeue >/dev/null 2>&1 || {
  printf 'ERROR: squeue is not available in this environment\n' >&2
  exit 127
}

printf '%s\n' '--- Array summary ---'
squeue -j "$ARRAY_JOB_ID" \
  -o '%.20i %.9P %.24j %.2t %.10M %.6D %R'
printf '\n%s\n' '--- Expanded array elements ---'
squeue -r -j "$ARRAY_JOB_ID" \
  -o '%.20i %.2t %.10M %.16R %N'

if command -v sacct >/dev/null 2>&1; then
  printf '\n%s\n' '--- Accounting states available so far ---'
  sacct -nX -P -j "$ARRAY_JOB_ID" -o JobIDRaw,State,ExitCode \
    | awk -F'|' -v id="$ARRAY_JOB_ID" '$1 ~ ("^" id "_[0-9]+$") {print}'
fi
