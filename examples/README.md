# Synthetic SLURM Array Example

Use this small, runnable pipeline to rehearse the pattern we want in lab jobs before adapting it to real data. It is intentionally plain: every step can be opened, run, and inspected.

1. one stable manifest row defines one task;
2. one worker validates and processes exactly one row;
3. local smoke tests prove the worker before scheduling;
4. a dynamically sized, throttled array fans out the work;
5. task-specific logs and atomic files preserve evidence;
6. an `afterok` dependency fans in to a defensive combine step;
7. failed elements can be diagnosed and rerun without deleting successful work.

> **Training only:** The generated observations, effect estimates, and p-values are deterministic synthetic examples. They are not valid scientific analyses.

## What you need

- Bash 3.2 or newer. The wrappers work with the stock Bash included with macOS.
- Python 3.10 or newer. The example uses only the Python standard library; there is no package installation step.
- `sbatch`, `squeue`, and `sacct` only when you move from the local practice run to a SLURM cluster.

The scripts stop with a clear error if the selected Python is older than 3.10. Use `--python /path/to/python3` on submission wrappers, or set `PYTHON_BIN`, when the cluster default is older.

## Quick local run

Enter this example's top-level directory first: use `cd examples` from a repository clone, or `cd slurm-example-pipeline` after extracting the standalone ZIP. The directory should contain `analysis/`, `data/`, `scripts/`, and `slurm/`.

The one-row run should finish in a few seconds and gives you one small file to inspect:

```bash
./scripts/run_local.sh 3
head results/local/task_003.csv
```

Then run and combine the complete manifest:

```bash
./scripts/run_all_local.sh --clean
```

After the complete run, `results/local-all/` should contain:

- `task_001.csv` through `task_024.csv`: one validated row per manifest task;
- `combined_results.csv`: all 24 rows plus FDR-adjusted p-values;
- `summary.md`: a short, readable QC summary; and
- `.slurm-playbook-run`: a hidden ownership and manifest-version marker used by the cleanup and recovery guards.

Relative `--results-dir` paths are resolved from the directory where you invoke the wrapper. `--clean` recursively clears only an empty directory or one carrying this pipeline's ownership marker; it refuses a populated, unmarked directory.

Run the isolated smoke test used by continuous integration:

```bash
./scripts/test_local_pipeline.sh
```

The final line should be:

```text
PASS: local outputs, safe cleanup, guarded recovery, and scheduler commands all checked out.
```

## Before live submission

Set these once for the cluster sections below:

```bash
export SLURM_ACCOUNT='<your-account>'
export SLURM_PARTITION='<your-partition>'
```

Confirm both values with the administrator for your project allocation. If the lab is unsure, check the [Great Lakes user guide](https://documentation.its.umich.edu/arc-hpc/greatlakes/user-guide) or ask ARC rather than guessing.

## Submit one job

Create the log directory before `sbatch` because SLURM does not create parent directories:

```bash
mkdir -p logs
TASK_ID=3 sbatch \
  --account="$SLURM_ACCOUNT" \
  --partition="$SLURM_PARTITION" \
  --export=ALL,TASK_ID \
  slurm/single.sbatch
```

The resource envelope in the example is deliberately small. Profile a real worker and revise it from evidence.

## Submit the array

```bash
./scripts/submit_array.sh --max-concurrent 8
```

The wrapper validates the manifest and builds the array specification from its actual task IDs. It does not assume the IDs are `1..N`, so a valid non-contiguous manifest becomes a non-contiguous SLURM array. It also gives `sbatch` an explicit project working directory and absolute log paths, which makes submission reliable from any caller directory.

## Submit fan-out plus fan-in

```bash
./scripts/submit_pipeline.sh --max-concurrent 8
```

The combine job uses `--dependency=afterok:<array_job_id>`. It checks that every manifest task has exactly one coherent result before publishing final files and applying Benjamini-Hochberg FDR correction.

For a recovery, submit the replacement array and replacement combine together:

```bash
./scripts/submit_pipeline.sh \
  --tasks '6,11,19' \
  --max-concurrent 3 \
  --results-dir results/48123110
```

A partial `--tasks` selection is accepted only when `--results-dir` is a pre-existing pipeline-owned run. Before contacting SLURM, the wrapper validates the marker and every unselected result against the current manifest. The selected files may be missing or bad—that is why they are being rerun. As each selected task starts, it removes any older result for that task before work that might fail; a failed retry therefore cannot leave a plausible stale result for the combine stage.

## Monitor and diagnose

Replace `ARRAY_JOB_ID` below with the numeric base array ID printed by `submit_pipeline.sh`.

```bash
./scripts/monitor.sh ARRAY_JOB_ID
./scripts/sacct_summary.sh ARRAY_JOB_ID
./scripts/rerun_failed.sh ARRAY_JOB_ID
```

`rerun_failed.sh` only prepares a suggested `submit_pipeline.sh` command. It intentionally does not resubmit until you have reviewed the state, exit code, and element-specific logs. Using the pipeline wrapper matters: it attaches a fresh `afterok` combine job to the replacement array.

## What is deterministic—and what is not

The synthetic observations and reported estimates (`beta`, standard error, z-score, p-value, and binary event rate) are deterministic for a fixed manifest and this version of the worker. They are useful for checking data flow, not for scientific interpretation.

`runtime_seconds` is a real wall-clock measurement, so it varies with the machine and system load. `resource_class` is teaching metadata carried through the files; it does not automatically change the `#SBATCH` requests. Likewise, `work` is an input to this toy data generator, not a calibrated prediction of CPU time.

These tasks are deliberately tiny. On a real cluster, scheduler startup and filesystem traffic may cost more than the computation itself. Keep the pattern, but bundle very short real tasks or use a different execution strategy when accounting evidence shows that scheduler overhead dominates.

## Important implementation details

- `scripts/runtime_setup.sh` sets common numerical-library thread limits from `SLURM_CPUS_PER_TASK` and prints runtime context. Replace its placeholder environment setup with approved modules or Conda activation.
- `slurm/array.sbatch` does not contain `#SBATCH --array`; the submission wrapper derives the range from the manifest and sets the concurrency cap.
- Account and partition are not hard-coded into reusable batch files.
- The teaching wrapper uses SLURM's default-style `--export=ALL` behavior after setting required runtime variables. For production, review the submitting shell for credentials or unrelated environment state, and replace this with an explicit export policy when the cluster/runtime permits it.
- Each worker publishes with an atomic rename, so a killed process does not leave a plausible partial CSV.
- Each result stores a SHA-256 fingerprint of its manifest row. The combine step refuses results from a mismatched manifest version.
- The combine step rejects missing, empty, duplicate, stale, or unexpected task files.
- Numeric validation rejects NaN and infinity as well as invalid ranges.
- Result directories carry a hidden marker so cleanup and partial recovery fail closed instead of guessing which directory is safe.
- The optional `SIMULATE_FAILURE_TASK_ID` environment variable supports failure training without corrupting output:

  ```bash
  SIMULATE_FAILURE_TASK_ID=11 ./scripts/run_local.sh 11
  ```

## Adaptation checklist

- Keep `task_id` stable and unique.
- Replace manifest fields with real input paths, parameters, seeds, and optional resource classes.
- Replace the synthetic worker, but retain strict input validation, one-result-per-task behavior, atomic writes, and non-zero failures.
- Tune CPU, memory, and walltime from representative `seff`/`sacct` evidence.
- Split heterogeneous work into separately sized arrays rather than sizing every element for the largest outlier.
- Add domain-specific completeness and scientific QC before final aggregation.
- Store PHI only in approved environments and never send sensitive logs, paths, or data to unapproved external AI services.
