#!/usr/bin/env bash
# Show final states and resource use for a completed job or array.
set -Eeuo pipefail

[[ $# -eq 1 && $1 =~ ^[1-9][0-9]*$ ]] || {
  printf 'Usage: ./scripts/sacct_summary.sh JOB_ID\n' >&2
  exit 64
}
JOB_ID=$1

command -v sacct >/dev/null 2>&1 || {
  printf 'ERROR: sacct is not available in this environment\n' >&2
  exit 127
}

sacct -j "$JOB_ID" --units=G \
  --format=JobID,JobName%24,State,Elapsed,AllocCPUS,ReqMem,MaxRSS,ExitCode
