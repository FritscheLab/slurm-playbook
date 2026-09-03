# Synthetic SLURM Array Example

This runnable example demonstrates one recoverable fan-out/fan-in pipeline with 24 deterministic synthetic tasks. It uses only Bash and the Python standard library.

> **Training only:** The generated estimates are not valid scientific analyses.

## Read the pipeline in this order

You do not need to understand every support file at once. Start with:

1. `data/manifest.tsv` — one stable row per task;
2. `analysis/analyze_one_trait.py` — one row in, one result out;
3. `slurm/array.sbatch` — maps `SLURM_ARRAY_TASK_ID` to the worker;
4. `scripts/submit_array.sh` — builds and throttles the array;
5. `scripts/submit_pipeline.sh` — attaches the `afterok` combine job; and
6. `slurm/combine.sbatch` — validates and combines the task results.

The other files support local testing, monitoring, accounting, and targeted recovery. In particular, `analysis/pipeline_guard.py` is supporting safety code; it is not required to understand the central SLURM mapping.

## Requirements

- Bash 3.2 or newer;
- Python 3.10 or newer; and
- `sbatch`, `squeue`, and `sacct` only for the cluster sections.

Set `PYTHON_BIN` if the appropriate interpreter is not named `python3`.

Run commands from this directory: `examples/` in a repository clone or `slurm-example-pipeline/` from the ZIP.

## Run locally

Run one task:

```bash
./scripts/run_local.sh 3
head results/local/task_003.csv
```

Run and combine all 24 tasks:

```bash
./scripts/run_all_local.sh --clean
```

This produces `task_001.csv` through `task_024.csv`, `combined_results.csv`, `summary.md`, and the hidden `.slurm-playbook-run` ownership marker under `results/local-all/`.

Run the scheduler-free integration test:

```bash
./tests/test_local_pipeline.sh
```

Its final line should be:

```text
PASS: local workflow, guarded recovery, and scheduler commands checked.
```

## Configure submission

Set the cluster-specific values in your shell rather than hard-coding them in reusable batch files:

```bash
export SLURM_ACCOUNT='<your-account>'
export SLURM_PARTITION='<your-partition>'
```

The submission wrappers accept four operational options:

```text
--max-concurrent N
--tasks SPEC
--results-dir DIR
--dry-run
```

Use space-separated values such as `--max-concurrent 8`. For targeted recovery, use `--tasks` together with the existing `--results-dir`.

## Inspect a dry run

Placeholder account and partition values are safe here because nothing is submitted:

```bash
SLURM_ACCOUNT=training SLURM_PARTITION=standard \
  ./scripts/submit_pipeline.sh --max-concurrent 8 --dry-run
```

The output shows the array submission and its `afterok` combine dependency.

## Submit on SLURM

Submit one task directly when you want a small acceptance check:

```bash
mkdir -p logs
TASK_ID=3 sbatch \
  --account="$SLURM_ACCOUNT" \
  --partition="$SLURM_PARTITION" \
  --export=ALL,TASK_ID \
  slurm/single.sbatch
```

Submit only the array:

```bash
array_submission=$(./scripts/submit_array.sh --max-concurrent 8)
printf '%s\n' "$array_submission"
```

Submit the array and combine job together:

```bash
submission=$(./scripts/submit_pipeline.sh --max-concurrent 8)
printf '%s\n' "$submission"
```

The pipeline receipt contains `array_job`, `combine_job`, and `results_dir`. The combine job becomes eligible only after every array element succeeds.

## Monitor and inspect accounting

Replace `ARRAY_JOB_ID` with the numeric ID from the submission receipt:

```bash
./scripts/monitor.sh ARRAY_JOB_ID
./scripts/sacct_summary.sh ARRAY_JOB_ID
```

The first command shows live queue state. The second shows completed accounting records and resource use.

## Recover failed elements

Diagnose the element-specific logs first. Then ask the helper to identify terminal failures and prepare a command; it never submits automatically:

```bash
./scripts/rerun_failed.sh ARRAY_JOB_ID results/ARRAY_JOB_ID
```

To use a smaller concurrency cap in the suggested recovery command:

```bash
MAX_CONCURRENT=3 ./scripts/rerun_failed.sh ARRAY_JOB_ID results/ARRAY_JOB_ID
```

After correcting the cause, run its suggested `submit_pipeline.sh` command. A recovery reuses the existing result directory, reruns only the selected IDs, and attaches a replacement combine job. The guard verifies the ownership marker and every result that will be reused before contacting SLURM.

## Details worth preserving when adapting

- One stable manifest row maps to one task ID and one result file.
- `%A` and `%a` give every array element distinct log names.
- The wrapper derives task IDs from the manifest and limits simultaneous work.
- Workers publish task results atomically and exit non-zero on failure.
- The combine stage rejects incomplete or stale results.
- Recovery never deletes successful task outputs blindly.
- Account and partition remain submission-time choices.
- Thread limits follow `SLURM_CPUS_PER_TASK`.

Replace the synthetic worker and manifest fields for real work, then measure representative tasks and revise CPU, memory, and walltime from evidence.
