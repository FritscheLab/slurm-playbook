---
layout: default
title: Arrays and Manifests
parent: Core Guide
nav_order: 5
---

# Arrays and manifests

Use a job array when the analysis consists of many independent work units that can each run through the same worker interface.

## Why the serial loop is an anti-pattern

Putting 24 independent models inside one allocation creates four problems:

- no concurrency—the tasks wait in a line;
- coarse recovery—a late failure can force a large rerun;
- one envelope—every task is sized for the largest;
- weak provenance—logs and outputs are harder to map to one scientific unit.

## One stable row = one task

A manifest makes inputs, seeds, task size, and optional resource classes explicit:

```text
task_id  phenotype          outcome_type  n      seed  work  resource_class
1        pain_burden        continuous    42000  1101  5     small
2        fatigue_score      continuous    38000  1102  5     small
6        fibromyalgia_code  binary        48000  1106  7     medium
24       diabetes_code      binary        50000  1124  6     medium
```

A good manifest is:

- **auditable:** task-defining inputs are visible;
- **stable:** task 6 always refers to the same work unit;
- **subsettable:** rerun `6,11,19` without renaming files;
- **extensible:** add chunk, resource class, or expected-output fields later.

{: .danger }
Do not use directory listing order as an implicit scheduler API. File order can change and is difficult to audit.

## Worker responsibility

The worker should handle exactly one row:

```bash
python3 analysis/analyze_one_trait.py \
  --manifest data/manifest.tsv \
  --task-id 6 \
  --output results/local/task_006.csv
```

The contract is:

1. validate the task ID;
2. read exactly one manifest row;
3. run one model;
4. write one result file atomically;
5. exit non-zero on any failure.

## Map one array element to one worker

The complete tested implementation is [`examples/slurm/array.sbatch`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/slurm/array.sbatch). Its central mapping is:

```bash
TASK_ID="${SLURM_ARRAY_TASK_ID:?}"
RESULTS_DIR="${RESULTS_DIR_OVERRIDE:-results/${SLURM_ARRAY_JOB_ID:?}}"
printf -v OUTPUT '%s/task_%03d.csv' "$RESULTS_DIR" "$TASK_ID"

"$PYTHON_BIN" analysis/analyze_one_trait.py \
  --manifest data/manifest.tsv \
  --task-id "$TASK_ID" \
  --output "$OUTPUT"
```

`SLURM_ARRAY_TASK_ID` selects the row. `%A` is the array job ID and `%a` is the task index in log filenames. Use the complete file for a real submission: it also establishes the project root and runtime, validates the guarded result directory, invalidates a stale aggregate, and logs context.

## Submit dynamically and throttle

```bash
export SLURM_ACCOUNT='<your-account>'
export SLURM_PARTITION='<your-partition>'
array_submission=$(./scripts/submit_array.sh --max-concurrent 8)

printf '%s\n' "$array_submission"
```

The wrapper reads account and partition from the exported variables, validates the manifest, derives the array expression from its actual task IDs, creates the log directory, supplies absolute log and working-directory paths, and adds the `%8` concurrency cap. It prints both the array job ID and result directory. Run it once with `--dry-run` if you want to inspect the resulting `sbatch` command before submission.

## One envelope still applies

All elements of one array start with the same CPU, memory, and time request. When tasks differ materially:

1. add a `resource_class` field;
2. submit separate small, medium, and large arrays;
3. reduce extreme chunks if possible;
4. consider a workflow engine when per-process rules and dependencies multiply.

## I/O-aware arrays

Array parallelism can turn a clean single-task workflow into an I/O storm. Throttle when tasks all read one huge file, write thousands of tiny files, or hit the same metadata service. Where practical, stage shared inputs once per node or use chunked formats designed for concurrent access.
