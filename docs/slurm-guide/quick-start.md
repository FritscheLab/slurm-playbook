---
layout: default
title: Start Here
nav_order: 2
permalink: /start-here/
has_toc: true
---

# Start here: prove, inspect, then submit

This path uses the repository's tested synthetic pipeline, so you can learn the moving parts without bringing your own data. By the end, you will have run one manifest row, validated all 24 rows without a scheduler, inspected a safe submission dry run, and—if you have cluster access—completed a small Great Lakes fan-out/fan-in run.

You do not need a cluster account for the first five checkpoints. Take them in order; each one gives you evidence that the next step is worth trying.

{: .key }
Run every command in this page from the example's top-level directory: the directory that contains `analysis/`, `data/`, `scripts/`, and `slurm/`.

## Before you begin

You need:

- a Unix-like shell with **Bash 3.2 or newer**;
- **Python 3.10 or newer** available as `python3`;
- no third-party Python packages;
- for the live checkpoint only, Great Lakes access plus a valid SLURM account and partition.

You can confirm the local versions with `bash --version` and `python3 --version`.

### Background refresher

This playbook assumes you already recognize CPU, RAM, disk, basic profiling, and good shared-system etiquette. If any of those feel new, review the two [earlier CSG cluster sessions]({{ site.baseurl }}{% link references.md %}#recommended-background-earlier-csg-sessions) first. They are excellent conceptual background, but their 2018 operational details are historical; use this playbook's U-M reference for current cluster policy.

This playbook focuses on single-node CPU jobs: serial programs, explicitly threaded programs, process pools confined to one node, independent array work, and one downstream combine stage. It does not cover MPI, multi-node execution, GPUs, cluster administration, or project-specific compliance decisions.

## 1. Enter the example directory

Choose one route.

### From a repository clone

```bash
git clone https://github.com/FritscheLab/slurm-playbook.git
cd slurm-playbook/examples
```

If the repository is already cloned, run `cd examples` from its root.

### From the standalone ZIP

[Download the example pipeline ZIP]({{ site.baseurl }}/assets/downloads/slurm-example-pipeline.zip), then run:

```bash
unzip slurm-example-pipeline.zip
cd slurm-example-pipeline
```

The archive already contains the `slurm-example-pipeline/` top-level directory; do not add an extra `examples/` to this path.

**Checkpoint:** all four paths should exist:

```bash
test -f data/manifest.tsv &&
  test -x scripts/run_local.sh &&
  test -f analysis/analyze_one_trait.py &&
  test -f slurm/array.sbatch &&
  printf 'PASS: example files are in place.\n'
```

You should see `PASS: example files are in place.`

## 2. Prove one work unit locally

Run manifest task 3 without SLURM:

```bash
./scripts/run_local.sh 3
```

The command prints its runtime context, the selected phenotype, and a `published=.../task_003.csv` line.

**Checkpoint:** inspect the one-row result:

```bash
test -s results/local/task_003.csv
sed -n '1,2p' results/local/task_003.csv
```

You should see a header and one data row whose `task_id` is `3`. The numbers are deterministic synthetic training output, not scientific findings.

## 3. Test the complete workflow locally

```bash
./tests/test_local_pipeline.sh
```

The test executes and combines all 24 work units in an isolated temporary directory. It also verifies deliberate failure, atomic publication, manifest fingerprints, invalid task rejection, and safe partial-recovery behavior.

**Checkpoint:** the last line is:

```text
PASS: local workflow, guarded recovery, and scheduler commands checked.
```

If this checkpoint fails, stop before submitting. Read the first `ERROR:` line and confirm the Python and Bash versions.

## 4. Inspect the failure contract

```bash
failure_dir=$(mktemp -d "${TMPDIR:-/tmp}/slurm-failure-demo.XXXXXX")
SIMULATE_FAILURE_TASK_ID=11 \
  ./scripts/run_local.sh 11 --results-dir "$failure_dir"
```

This command is expected to exit non-zero. The worker fails before atomic publication.

**Checkpoint:** no plausible result was left behind:

```bash
test ! -e "$failure_dir/task_011.csv"
```

An exit status of 0 confirms the failed task did not publish `task_011.csv`. You can remove the temporary directory when you are finished inspecting it.

## 5. Validate submission without a scheduler

Use placeholders with `--dry-run`; they are not sent to SLURM:

```bash
SLURM_ACCOUNT=training SLURM_PARTITION=standard \
  ./scripts/submit_pipeline.sh \
  --max-concurrent 8 \
  --dry-run
```

Read the printed `sbatch` command. It should derive the array range from the manifest, cap concurrency at eight, use absolute script paths, and describe an `afterok` combine dependency.

**Checkpoint:** stdout includes:

```text
array_job=DRY_RUN combine_job=DRY_RUN results_dir=DRY_RUN
```

## 6. Run the Great Lakes acceptance check

Skip this checkpoint if you do not yet have cluster access. Before submitting, check the [U-M Cluster Reference]({{ site.baseurl }}{% link cluster-reference.md %}) and confirm the account and partition with your project's Great Lakes account administrator. If nobody in the lab knows which values apply, use the [ARC Great Lakes user guide](https://documentation.its.umich.edu/arc-hpc/greatlakes/user-guide) rather than guessing.

```bash
export SLURM_ACCOUNT='<your-account>'
export SLURM_PARTITION='<your-partition>'
submission=$(./scripts/submit_pipeline.sh --max-concurrent 8)
printf '%s\n' "$submission"

array_job=${submission#array_job=}
array_job=${array_job%% *}
combine_job=${submission#* combine_job=}
combine_job=${combine_job%% *}
results_dir=${submission#* results_dir=}
```

The wrapper prints one line containing `array_job=...`, `combine_job=...`, and `results_dir=...`. The last five lines save that run context for the checks below, including project paths that contain spaces.

Monitor the fan-out and inspect accounting:

```bash
./scripts/monitor.sh "$array_job"
./scripts/sacct_summary.sh "$array_job"
scontrol show job "$combine_job"
```

After the combine job completes, inspect the run directory reported at submission:

```bash
test -s "$results_dir/combined_results.csv"
test -s "$results_dir/summary.md"
grep 'Validated task results' "$results_dir/summary.md"
```

**Checkpoint:** all 24 array elements and the combine job report `COMPLETED`; `summary.md` reports 24 validated task results.

{: .cluster }
This example is tested on Great Lakes. You can use the same scheduler pattern on Armis2 after checking its current account, partition, storage, billing, and sensitive-data policies; a duplicate training run is not needed.

## 7. Recover only failed elements

For a real failed array, diagnose the element-specific logs first:

```bash
./scripts/rerun_failed.sh "$array_job" "$results_dir"
```

The helper does not submit anything. After correcting the cause, run the `submit_pipeline.sh` command it suggests. That command targets the **existing** result directory and schedules a replacement combine job. Do not point a partial recovery at a new directory: the combine stage needs the successful original results as well as the replacements.

## Continue learning

- Use the [Core Guide]({{ site.baseurl }}{% link slurm-guide/index.md %}) to understand and adapt each pattern.
- Keep the [Worked Example]({{ site.baseurl }}{% link example-pipeline.md %}) open when copying tested files.
- Use [Commands and Templates]({{ site.baseurl }}{% link quick-reference.md %}) for lookup after you understand the workflow.
- If a checkpoint is unclear or fails, [open an issue](https://github.com/FritscheLab/slurm-playbook/issues/new) with the page, command, and a non-sensitive excerpt of the output.
