---
layout: default
title: Worked Example
nav_order: 4
has_toc: true
---

# Worked example: a runnable synthetic pipeline

[Download the standalone example ZIP]({{ site.baseurl }}/assets/downloads/slurm-example-pipeline.zip){: .btn .btn-primary }

This is the safest place to borrow code from in the playbook. It implements the full pattern with 24 deterministic synthetic phenotype tasks: one stable manifest row per work unit, local testing, a dynamically sized throttled array, task-specific evidence, an `afterok` combine job, completeness validation, Benjamini–Hochberg correction, and targeted recovery.

{: .caution }
The calculations are training examples, not valid scientific models or findings. Replace the worker for real work while preserving its explicit interface, validation, and non-zero failure behavior.

## Requirements and working directory

The local workflow requires Bash 3.2+ and Python 3.10+ and installs no third-party packages. Live submission additionally requires SLURM commands and a valid Great Lakes account and partition.

Use one of these two directory layouts:

- **Repository clone:** from the repository root, run `cd examples`.
- **Downloaded ZIP:** unzip `slurm-example-pipeline.zip`, then run `cd slurm-example-pipeline`.

In either case, run every command below from the directory containing `analysis/`, `data/`, `scripts/`, and `slurm/`. The downloaded ZIP does **not** contain an additional `examples/` directory.

## Repository layout

<pre class="file-tree">examples/                        # repository clone
├── analysis/
│   ├── analyze_one_trait.py
│   ├── combine_results.py
│   └── pipeline_guard.py
├── data/
│   └── manifest.tsv
├── scripts/
│   ├── runtime_setup.sh
│   ├── run_local.sh
│   ├── run_all_local.sh
│   ├── submit_array.sh
│   ├── submit_pipeline.sh
│   ├── monitor.sh
│   ├── sacct_summary.sh
│   ├── rerun_failed.sh
│   └── test_local_pipeline.sh
└── slurm/
    ├── single.sbatch
    ├── array.sbatch
    └── combine.sbatch</pre>

The standalone archive has the same contents under `slurm-example-pipeline/`.

## Follow one walkthrough

[Start Here]({{ site.baseurl }}{% link slurm-guide/quick-start.md %}) is the step-by-step route for both a repository clone and the standalone ZIP. It takes you through one local task, the full scheduler-free test, a submission dry run, the Great Lakes check, and recovery without making you reconcile two sets of instructions.

Come back to this page when you want to understand or adapt the implementation.

{: .cluster }
The scheduler path is tested on Great Lakes. The same pattern can be used on Armis2 after checking its current account, partition, storage, billing, and sensitive-data policies; a duplicate training run is not needed.

## How the pieces fit

| File or directory | Responsibility |
|---|---|
| `data/manifest.tsv` | Gives every work unit a stable, explicit task ID and carries teaching metadata. |
| `analysis/analyze_one_trait.py` | Validates one manifest row, runs one synthetic task, and publishes one CSV atomically. |
| `analysis/pipeline_guard.py` | Validates task selections, protects result directories, and checks recovery preconditions. |
| `analysis/combine_results.py` | Rejects incomplete or stale result sets, applies Benjamini–Hochberg correction, and publishes the aggregate. |
| `scripts/runtime_setup.sh` | Enforces Python 3.10+, caps common hidden thread pools, and prints runtime context. |
| `scripts/run_*.sh` | Provides the local one-task and complete-workflow interfaces. |
| `scripts/submit_*.sh` | Derives array IDs, supplies absolute scheduler paths, throttles concurrency, and attaches the fan-in dependency. |
| `scripts/monitor.sh`, `sacct_summary.sh`, `rerun_failed.sh` | Keeps monitoring, accounting, diagnosis, and recovery close to the runnable example. |
| `slurm/*.sbatch` | Defines the small single-job, array-worker, and combine allocations without hard-coded accounts. |
| `scripts/test_local_pipeline.sh` | Exercises the happy path, deliberate failures, stale-output guards, cleanup safety, recovery, and mocked scheduler commands. |

## Expected result set

A complete local run or successful array plus combine produces this shape:

```text
results/RUN_ID/
├── .slurm-playbook-run
├── task_001.csv
├── …
├── task_024.csv
├── combined_results.csv
└── summary.md
```

The hidden marker records pipeline ownership and the manifest digest; it is what lets cleanup and partial recovery fail closed. The task estimates are deterministic synthetic values. `runtime_seconds` is a real measurement and will vary by machine and load.

## Safety properties worth preserving

- Account and partition are supplied at submission, not hard-coded in batch files.
- The wrapper derives the full array range from `data/manifest.tsv`.
- Each worker publishes with an atomic rename, so an interrupted process cannot leave a plausible partial CSV.
- Every result stores a SHA-256 fingerprint of its manifest row.
- Aggregation rejects missing, empty, duplicate, stale, and unexpected task files.
- Runtime setup caps common numerical-library thread counts at `SLURM_CPUS_PER_TASK`.
- Unique array log names include both job and task IDs.

## Adapt it to a real pipeline

1. Keep `task_id` stable and unique.
2. Replace synthetic fields with explicit input identifiers, parameters, seeds, and optional resource classes.
3. Replace `analyze_one_trait.py` with a worker that consumes exactly one row, validates one output, and exits non-zero on failure.
4. Measure representative tasks and update CPU, memory, and time in `slurm/array.sbatch`.
5. Replace the runtime placeholder with approved modules or environments.
6. Add domain-specific completeness and scientific QC without weakening the existing publication guards.
7. Split heterogeneous work into separate submissions rather than sizing every task for the largest outlier.

For the shortest guided route through these commands, use [Start Here]({{ site.baseurl }}{% link slurm-guide/quick-start.md %}).
