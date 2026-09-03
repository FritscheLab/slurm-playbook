---
layout: default
title: Worked Example
nav_order: 4
has_toc: true
---

# Worked example: a runnable synthetic pipeline

[Download the example ZIP]({{ site.baseurl }}/assets/downloads/slurm-example-pipeline.zip){: .btn .btn-primary }
[Browse files on GitHub](https://github.com/FritscheLab/slurm-playbook/tree/main/examples){: .btn }

This example is complete and recoverable, but you do not need to understand every safeguard before learning the SLURM pattern. Start with the short reading path below; open the supporting files only when you reach the problem they solve.

{: .caution }
The calculations are training examples, not valid scientific models or findings. Replace the worker for real work while preserving its explicit input, output, and non-zero failure behavior.

## Read these files first

The central flow is:

```text
manifest row → one worker → one array element → afterok → combine
```

| Order | File | What to look for |
|---:|---|---|
| 1 | [`data/manifest.tsv`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/data/manifest.tsv) | One stable task ID and its inputs per row. |
| 2 | [`analysis/analyze_one_trait.py`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/analysis/analyze_one_trait.py) | One row in, one predictably named result out. |
| 3 | [`slurm/array.sbatch`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/slurm/array.sbatch) | `SLURM_ARRAY_TASK_ID` mapped to that worker and `%A_%a` log names. |
| 4 | [`scripts/submit_array.sh`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/scripts/submit_array.sh) | Manifest-derived array IDs and the concurrency cap. |
| 5 | [`scripts/submit_pipeline.sh`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/scripts/submit_pipeline.sh) | The array submission followed by one `afterok` combine submission. |
| 6 | [`slurm/combine.sbatch`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/slurm/combine.sbatch) | The fan-in job calling the result combiner. |

[Start Here]({{ site.baseurl }}{% link slurm-guide/quick-start.md %}) runs this flow locally and shows a submission dry run before asking you to use a cluster.

## Requirements and working directory

The local workflow requires Bash 3.2+ and Python 3.10+ and installs no third-party packages. Live submission additionally requires SLURM commands and a valid Great Lakes account and partition.

- **Repository clone:** from the repository root, run `cd examples`.
- **Downloaded ZIP:** unzip `slurm-example-pipeline.zip`, then run `cd slurm-example-pipeline`.

Run commands from the directory containing `analysis/`, `data/`, `scripts/`, and `slurm/`.

## Repository layout

<pre class="file-tree">examples/
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
│   └── rerun_failed.sh
├── slurm/
│   ├── single.sbatch
│   ├── array.sbatch
│   └── combine.sbatch
└── tests/
    └── test_local_pipeline.sh</pre>

The standalone archive places the same contents under `slurm-example-pipeline/`.

## Supporting files: open them when needed

| Need | Files | Responsibility |
|---|---|---|
| Run without SLURM | [`run_local.sh`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/scripts/run_local.sh), [`run_all_local.sh`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/scripts/run_all_local.sh) | Exercise one task or the full pipeline locally. |
| Submit one task | [`single.sbatch`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/slurm/single.sbatch) | Run a small cluster acceptance check before the array. |
| Set up the process | [`runtime_setup.sh`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/scripts/runtime_setup.sh) | Check Python, cap hidden thread pools, and print runtime context. |
| Validate final output | [`combine_results.py`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/analysis/combine_results.py) | Reject an incomplete or incoherent result set before aggregation. |
| Monitor and account | [`monitor.sh`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/scripts/monitor.sh), [`sacct_summary.sh`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/scripts/sacct_summary.sh) | Show live task states and completed resource evidence. |
| Recover selected tasks | [`rerun_failed.sh`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/scripts/rerun_failed.sh) | Identify failed array elements and print a targeted resubmission command. |
| Protect reused results | [`pipeline_guard.py`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/analysis/pipeline_guard.py) | Check ownership, task selection, and unaffected results during recovery. |
| Verify the implementation | [`test_local_pipeline.sh`](https://github.com/FritscheLab/slurm-playbook/blob/main/examples/tests/test_local_pipeline.sh) | Exercise local output, recovery guards, and mocked scheduler commands. |

The safety helper is intentionally not part of the first reading path. Its extra logic exists because partial recovery reuses old task outputs; the simple SLURM mapping remains in `array.sbatch`.

## Submission interface

Set account and partition once in the shell:

```bash
export SLURM_ACCOUNT='<your-account>'
export SLURM_PARTITION='<your-partition>'
```

Then use `submit_array.sh` for only the fan-out stage or `submit_pipeline.sh` for fan-out plus fan-in. Their learner-facing options are limited to `--max-concurrent`, `--tasks`, `--results-dir`, and `--dry-run`. Use space-separated option values, as shown in the walkthrough.

## Expected result set

A complete run produces:

```text
results/RUN_ID/
├── .slurm-playbook-run
├── task_001.csv
├── …
├── task_024.csv
├── combined_results.csv
└── summary.md
```

The hidden marker and manifest fingerprints make selected-task recovery safe: unselected results must still match the current manifest before they are reused. `runtime_seconds` is a real measurement and will vary by machine and load.

## Adapt it to a real pipeline

1. Keep `task_id` stable and unique.
2. Replace manifest fields with explicit input identifiers, parameters, seeds, and optional resource classes.
3. Replace `analyze_one_trait.py` with a worker that consumes exactly one row and exits non-zero on failure.
4. Measure representative tasks and update CPU, memory, and time in `slurm/array.sbatch`.
5. Replace the runtime placeholder with approved modules or environments.
6. Add domain-specific completeness and scientific QC without weakening recovery validation.

For the guided command sequence, continue with [Start Here]({{ site.baseurl }}{% link slurm-guide/quick-start.md %}).
