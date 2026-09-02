---
layout: default
title: Robust Single Job
parent: Core Guide
nav_order: 3
---

# Anatomy of a robust single-node job

This is a **template** for adapting a local command. Replace the marked runtime and analysis lines. The complete tested counterpart is [`examples/slurm/single.sbatch`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/slurm/single.sbatch).

Create the output and log directories from the submission directory before calling `sbatch`:

```bash
mkdir -p logs results
```

```bash
#!/usr/bin/env bash
#SBATCH --job-name=analysis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -Eeuo pipefail
cd "${SLURM_SUBMIT_DIR:?}"

module purge
# module load python/<approved-version>

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export OPENBLAS_NUM_THREADS="$OMP_NUM_THREADS"
export MKL_NUM_THREADS="$OMP_NUM_THREADS"

printf 'timestamp=%s host=%s pwd=%s job_id=%s cpus=%s\n' \
  "$(date --iso-8601=seconds)" "$(hostname)" "$PWD" \
  "${SLURM_JOB_ID:-NA}" "${SLURM_CPUS_PER_TASK:-1}"

# Replace with the exact command already proven locally.
python3 analysis.py \
  --input data/small_example.tsv \
  --output results/task_001.csv

test -s results/task_001.csv
```

## Why each part exists

| Pattern | Purpose | Failure it prevents |
|---|---|---|
| Explicit CPU, memory, and time | Makes the resource envelope reviewable and measurable. | Hidden defaults, inconsistent behavior, unexplainable billing. |
| `%x` and `%j` in log names | Gives every job unique evidence tied to job name and ID. | Colliding logs and ambiguous failures. |
| `set -Eeuo pipefail` | Stops on errors, unset variables, and failed pipeline elements. | A batch script appearing `COMPLETED` after a masked command failure. |
| Runtime setup inside the script | Loads modules, Conda/R/Python environments, paths, and versions in the batch shell. | “Works on login, command not found in batch.” |
| `cd "${SLURM_SUBMIT_DIR:?}"` | Makes relative paths resolve from the submission directory. | Jobs starting in an unexpected working directory. |
| Context logging | Records host, IDs, executable, versions, timestamps, and thread settings. | Irreproducible or untraceable runs. |
| One explicit worker call | Keeps the scientific task separate from the scheduler wrapper. | Monolithic scripts that are difficult to test, array, or migrate. |
| Explicit output check | Makes missing publication a non-zero failure. | A scheduler success state with no usable result. |

## A useful runtime context function

```bash
print_job_context() {
  printf 'timestamp=%s\n' "$(date --iso-8601=seconds)"
  printf 'host=%s\n' "$(hostname)"
  printf 'pwd=%s\n' "$PWD"
  printf 'job_id=%s\n' "${SLURM_JOB_ID:-NA}"
  printf 'array_job_id=%s\n' "${SLURM_ARRAY_JOB_ID:-NA}"
  printf 'array_task_id=%s\n' "${SLURM_ARRAY_TASK_ID:-NA}"
  printf 'cpus_per_task=%s\n' "${SLURM_CPUS_PER_TASK:-1}"
  printf 'python=%s\n' "$(command -v python || true)"
  python --version 2>&1 || true
}
```

## Fail loudly and deliberately

A worker should return non-zero when it cannot produce a valid result. The combine stage should also fail when expected task outputs are missing, duplicated, stale, or malformed. SLURM dependencies only understand exit status; scientific completeness must be encoded in the scripts.

{: .caution }
`set -e` is helpful but not magical. Test error handling around conditionals, command substitutions, subshells, and tools that use non-zero statuses for ordinary control flow.

## Keep configuration out of reusable batch files

Do not hard-code a lab shortcode or a person's account in a batch file. Pass cluster-specific values at submission time:

```bash
export SLURM_ACCOUNT='<your-account>'
export SLURM_PARTITION='<your-partition>'
sbatch \
  --account="$SLURM_ACCOUNT" \
  --partition="$SLURM_PARTITION" \
  slurm/analysis.sbatch
```

This keeps the worker portable across accounts and makes the billing choice visible in the submission command.
