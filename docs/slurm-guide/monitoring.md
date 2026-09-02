---
layout: default
title: Monitoring and Accounting
parent: Core Guide
nav_order: 7
---

# Monitoring and accounting

Treat an array as both one workflow and many independently observable tasks.

In the commands below, replace `JOB_ID` with one job ID and `ARRAY_JOB_ID` with the base ID printed by the submission wrapper. They are visible placeholders, not shell variables.

## While queued or running

```bash
squeue -j JOB_ID
squeue -r -j ARRAY_JOB_ID
scontrol show job -dd JOB_ID
```

A useful format includes job ID, partition, name, state, elapsed time, nodes, and reason:

```bash
squeue -j ARRAY_JOB_ID \
  -o '%.20i %.9P %.24j %.2t %.10M %.6D %R'
```

Read the reason literally. For example, `JobArrayTaskLimit` is expected when the `%K` concurrency cap is doing its job.

Follow one element's log:

```bash
tail -f logs/trait_array_ARRAY_JOB_ID_6.out
```

For a running batch step, `sstat` can show live CPU and memory statistics:

```bash
sstat -j JOB_ID.batch --format=AveCPU,AveRSS,MaxRSS
```

## After completion: one job

```bash
seff JOB_ID
```

`seff` is a fast diagnostic summary. Interpret CPU efficiency, memory efficiency, wall-clock time, and terminal state together with the application log.

## After completion: the whole array

```bash
sacct -j ARRAY_JOB_ID --units=G \
  -o JobIDRaw,State,Elapsed,Timelimit,AllocCPUS,ReqMem,MaxRSS,TotalCPU,ExitCode
```

Look at distributions rather than a single task:

- median and upper-tail elapsed time;
- largest MaxRSS;
- failed states and exit codes;
- task-size outliers;
- clusters of slow tasks that may share an input or resource class.

{: .key }
One `seff` report is a clue. Array-wide `sacct` is evidence.

## Why MaxRSS can look blank

Some accounting layouts place memory on the `.batch` step rather than the allocation row. Do not conclude that memory was zero. Include steps or explicitly inspect `JOB_ID.batch`.

## Log naming patterns

| Job type | Recommended stdout/stderr pattern |
|---|---|
| Single job | `logs/%x_%j.out` and `logs/%x_%j.err` |
| Array element | `logs/%x_%A_%a.out` and `logs/%x_%A_%a.err` |

Where:

- `%x` = job name;
- `%j` = job ID;
- `%A` = array job ID;
- `%a` = array task index.

## What every log should reveal

At minimum, record:

```text
start/end timestamps
hostname and working directory
job ID, array job ID, and array task ID
requested CPUs and thread limits
selected manifest row or input identifiers
executable path and version
output path
progress checkpoints
final validation and exit status
```

## Cancellation

```bash
scancel JOB_ID
scancel ARRAY_JOB_ID
scancel ARRAY_JOB_ID_6
```

Canceling one element preserves the remaining array. Diagnose whether a cancellation was manual, time-limit related, dependency related, or caused by a node/system event before resubmitting.
