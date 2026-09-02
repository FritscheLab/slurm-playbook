#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -eq 1 && $1 =~ ^[0-9]+$ ]] || {
  printf 'Usage: ./scripts/sacct_summary.sh JOB_OR_ARRAY_ID\n' >&2
  exit 64
}
JOB_ID=$1
command -v sacct >/dev/null 2>&1 || {
  printf 'ERROR: sacct is not available in this environment\n' >&2
  exit 127
}

printf '%s\n' '--- Full accounting table (steps included; MaxRSS often appears on .batch) ---'
sacct -P -j "$JOB_ID" --units=G \
  -o JobIDRaw,State,Elapsed,Timelimit,AllocCPUS,ReqMem,MaxRSS,TotalCPU,ExitCode

printf '\n%s\n' '--- Array element state counts ---'
sacct -nX -P -j "$JOB_ID" -o JobIDRaw,State \
  | awk -F'|' -v id="$JOB_ID" '
      $1 ~ ("^" id "_[0-9]+$") {
        state=$2
        sub(/\+.*/, "", state)
        counts[state]++
      }
      END {
        for (state in counts) print state, counts[state]
      }
    ' | sort
