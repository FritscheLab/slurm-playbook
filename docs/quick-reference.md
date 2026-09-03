---
layout: default
title: Commands and Templates
nav_order: 5
has_children: true
has_toc: true
---

# Commands and templates

Use this page for command lookup. The snippets here are templates, not complete tested workflows: replace placeholders, confirm the execution model, and size resources from measurements. For files that run as provided, use the [Worked Example]({{ site.baseurl }}{% link example-pipeline.md %}).

[Download the optional quick-reference PDF]({{ site.baseurl }}/assets/downloads/slurm-session-cheatsheets.pdf){: .btn .btn-primary }

The PDF is a printable teaching aid and carries its own verification date. For cluster limits, storage rules, or data policy, use the maintained [U-M Cluster Reference]({{ site.baseurl }}{% link cluster-reference.md %}) and its official links.

## Submit

```bash
sbatch job.sbatch
sbatch --parsable job.sbatch
sbatch --array=1-24%8 array.sbatch
sbatch --dependency=afterok:12345 combine.sbatch
```

## Monitor

```bash
squeue -u "$USER"
squeue -r -j JOB_ID
squeue -j JOB_ID -o '%.20i %.9P %.24j %.2t %.10M %.6D %R'
scontrol show job -dd JOB_ID
```

## Inspect running usage

```bash
sstat -j JOB_ID.batch --format=AveCPU,AveRSS,MaxRSS
```

## Inspect completed usage

```bash
seff JOB_ID
seff ARRAY_ID_TASK_ID

sacct -j JOB_ID --units=G \
  -o JobIDRaw,State,Elapsed,Timelimit,AllocCPUS,ReqMem,MaxRSS,TotalCPU,ExitCode
```

## Cancel

```bash
scancel JOB_ID
scancel ARRAY_JOB_ID
scancel ARRAY_JOB_ID_6
```

## Array essentials

```bash
#SBATCH --output=logs/%x_%A_%a.out
#SBATCH --error=logs/%x_%A_%a.err

TASK_ID="${SLURM_ARRAY_TASK_ID:?}"
sbatch --array=1-24%8 array.sbatch
```

| Symbol | Meaning |
|---|---|
| `%x` | job name |
| `%j` | job ID |
| `%A` | array job ID |
| `%a` | array task index |
| `%8` in `1-24%8` | at most eight array elements running simultaneously |

All elements of one array share the same initial CPU, memory, and walltime request.

## Thread limits

```bash
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export OPENBLAS_NUM_THREADS="$OMP_NUM_THREADS"
export MKL_NUM_THREADS="$OMP_NUM_THREADS"
export NUMEXPR_NUM_THREADS="$OMP_NUM_THREADS"
```

Request more CPUs only when the program actually creates useful threads or worker processes.

## Dependencies and recovery

```bash
export SLURM_ACCOUNT='<your-account>'
export SLURM_PARTITION='<your-partition>'
submission=$(./scripts/submit_pipeline.sh --max-concurrent 8)
printf '%s\n' "$submission"

array_job=${submission#array_job=}
array_job=${array_job%% *}
results_dir=${submission#* results_dir=}

./scripts/sacct_summary.sh "$array_job"
./scripts/rerun_failed.sh "$array_job" "$results_dir"
```

The recovery helper reports failed terminal tasks and suggests the guarded resubmission command. Diagnose the logs and correct the cause before running that suggestion.

## Common pending reasons

| Reason | Meaning / first check |
|---|---|
| `Priority` | Higher-priority eligible work is ahead; inspect fair-share and wait. |
| `Resources` | Requested envelope cannot currently be placed; inspect CPU, memory, time, features. |
| `Dependency` | Upstream dependency is not satisfied. |
| `JobArrayTaskLimit` | The array's `%K` simultaneous-task cap has been reached; usually expected. |
| `AssocMaxSubmitJobLimit` / related | User/account association limit has been reached. |
| `QOS...` | A quality-of-service limit or policy applies. |

## Common terminal states

```text
COMPLETED
FAILED
OUT_OF_MEMORY
TIMEOUT
CANCELLED
NODE_FAIL
```

## Diagnostic order

```text
STATE / REASON
→ LOGS
→ EXIT CODE
→ RESOURCES
→ ENVIRONMENT
→ PATHS / PERMISSIONS
→ SHARED I/O
```
