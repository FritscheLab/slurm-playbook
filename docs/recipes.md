---
layout: default
title: Template Recipes
parent: Commands and Templates
nav_order: 1
has_toc: true
---

# Template recipes

These snippets are **templates**, not standalone tested programs. Replace placeholder commands and runtime setup, validate paths, and right-size every request from measurements. For complete tested files, use the [Worked Example]({{ site.baseurl }}{% link example-pipeline.md %}).

## Set cluster values once

```bash
export SLURM_ACCOUNT='<your-account>'
export SLURM_PARTITION='<your-partition>'
```

Confirm both values with the administrator for your project allocation before submitting.

## Create required directories

```bash
mkdir -p logs results
```

## Robust serial Python job

```bash
#!/usr/bin/env bash
#SBATCH --job-name=analysis
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:10:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -Eeuo pipefail
cd "${SLURM_SUBMIT_DIR:?}"

module purge
# Load or activate the approved runtime for this project.

# Replace these paths with the command already proven locally.
python3 analysis.py --output results/analysis.csv
test -s results/analysis.csv
```

For R, use the same structure with the approved R module or environment, an `Rscript` command, and an explicit output check.

## Threaded job with library limits

```bash
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8

export OMP_NUM_THREADS="$SLURM_CPUS_PER_TASK"
export OPENBLAS_NUM_THREADS="$SLURM_CPUS_PER_TASK"
export MKL_NUM_THREADS="$SLURM_CPUS_PER_TASK"
export NUMEXPR_NUM_THREADS="$SLURM_CPUS_PER_TASK"

my_program --threads "$SLURM_CPUS_PER_TASK"
```

## Dynamic manifest array

```bash
array_job=$(./scripts/submit_array.sh \
  --account="$SLURM_ACCOUNT" \
  --partition="$SLURM_PARTITION" \
  --max-concurrent 8)

printf 'array_job=%s\n' "$array_job"
```

This tested wrapper uses the IDs that actually appear in the manifest, so it also handles a valid non-contiguous task set.

## Array element output path

```bash
TASK_ID="${SLURM_ARRAY_TASK_ID:?}"
printf -v OUTPUT 'results/%s/task_%03d.csv' \
  "$SLURM_ARRAY_JOB_ID" "$TASK_ID"
```

## Submit array plus combine dependency

```bash
submission=$(./scripts/submit_pipeline.sh \
  --account="$SLURM_ACCOUNT" \
  --partition="$SLURM_PARTITION" \
  --max-concurrent 8)

printf '%s\n' "$submission"
array_job=${submission#array_job=}
array_job=${array_job%% *}
results_dir=${submission#* results_dir=}
```

The wrapper submits the array first, then a combine job with an `afterok` dependency and the required result-directory context. The parameter expansion saves that context for the commands below, even when the project path contains spaces.

## Find failed elements

```bash
./scripts/rerun_failed.sh "$array_job" --results-dir "$results_dir"
```

The helper reports failed **terminal** elements and prints a recovery command; it does not mistake pending or running tasks for failures and does not submit anything automatically.

## Rerun a subset

```bash
./scripts/submit_pipeline.sh \
  --tasks '6,11,19' \
  --max-concurrent 3 \
  --results-dir "$results_dir"
```

Use the existing run directory so the guard can validate the successful task files and the wrapper can attach a replacement combine job.

## Interactive debug allocation

```bash
salloc \
  --account="$SLURM_ACCOUNT" \
  --partition=debug \
  --time=00:30:00 \
  --nodes=1 \
  --ntasks=1 \
  --cpus-per-task=4 \
  --mem=8G
```

## Array-wide accounting export

```bash
sacct -P -j "$array_job" --units=G \
  -o JobIDRaw,State,ElapsedRaw,TimelimitRaw,AllocCPUS,ReqMem,MaxRSS,TotalCPU,ExitCode \
  > "accounting_${array_job}.tsv"
```

## Context block for logs

```bash
printf 'start=%s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
printf 'host=%s pwd=%s\n' "$(hostname)" "$PWD"
printf 'job=%s array=%s task=%s cpus=%s\n' \
  "${SLURM_JOB_ID:-NA}" \
  "${SLURM_ARRAY_JOB_ID:-NA}" \
  "${SLURM_ARRAY_TASK_ID:-NA}" \
  "${SLURM_CPUS_PER_TASK:-1}"
```

For complete tested files, use the [example pipeline]({{ site.baseurl }}{% link example-pipeline.md %}).
