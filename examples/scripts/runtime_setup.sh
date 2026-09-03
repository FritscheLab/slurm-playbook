#!/usr/bin/env bash
# Shared runtime contract sourced by both local wrappers and batch scripts.
# Replace the placeholder Python setup with lab-approved modules/Conda as needed;
# sourcing keeps its exports and helper functions in the caller's shell.

# Fail on command errors and unset variables, including failures inside pipes.
set -Eeuo pipefail

# Honor a caller-supplied interpreter; otherwise establish the portable default.
: "${PYTHON_BIN:=python3}"
export PYTHON_BIN

# Keep common numerical libraries inside the CPU envelope even when a real
# worker imports packages that create hidden threads.
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export OPENBLAS_NUM_THREADS="$OMP_NUM_THREADS"
export MKL_NUM_THREADS="$OMP_NUM_THREADS"
export NUMEXPR_NUM_THREADS="$OMP_NUM_THREADS"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'ERROR: required command not found: %s\n' "$1" >&2
    return 127
  }
}

require_python_310() {
  require_command "$PYTHON_BIN" || return
  if ! "$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'; then
    python_version=$("$PYTHON_BIN" --version 2>&1 || printf 'unknown version')
    printf 'ERROR: Python 3.10 or newer is required; %s reports %s\n' \
      "$PYTHON_BIN" "$python_version" >&2
    return 65
  fi
  # Export an absolute executable path so a relative PYTHON_BIN value keeps
  # working after sbatch changes into the example project directory.
  resolved_python=$("$PYTHON_BIN" -c 'import sys; print(sys.executable)')
  [[ -n $resolved_python && $resolved_python == /* ]] || {
    printf 'ERROR: could not resolve an absolute Python executable from %s\n' \
      "$PYTHON_BIN" >&2
    return 65
  }
  PYTHON_BIN=$resolved_python
  export PYTHON_BIN
}

print_job_context() {
  # GNU date supports ISO output; the fallback also works on macOS login nodes.
  printf 'start=%s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
  printf 'host=%s\n' "$(hostname)"
  printf 'pwd=%s\n' "$PWD"
  printf 'job_id=%s array_job_id=%s array_task_id=%s\n' \
    "${SLURM_JOB_ID:-NA}" \
    "${SLURM_ARRAY_JOB_ID:-NA}" \
    "${SLURM_ARRAY_TASK_ID:-NA}"
  printf 'cpus_per_task=%s python=%s\n' \
    "${SLURM_CPUS_PER_TASK:-1}" \
    "$(command -v "$PYTHON_BIN" 2>/dev/null || printf 'NOT_FOUND')"
  # Context logging is diagnostic and should not itself fail an otherwise valid job.
  "$PYTHON_BIN" --version 2>&1 || true
}

# Validate immediately when sourced, before the caller starts expensive work.
require_python_310
