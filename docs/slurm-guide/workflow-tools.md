---
layout: default
title: Workflow Tools
parent: Core Guide
nav_order: 10
---

# Workflow tools: use the smallest abstraction that removes real complexity

Raw SLURM is a valuable foundation. Add a wrapper or workflow engine when it eliminates a recurring problem rather than merely hiding commands.

## Comparison

| Tool level | Best fit | What it removes | What it does not remove |
|---|---|---|---|
| Raw array | Homogeneous independent tasks | Manual loop, coarse recovery, ambiguous task mapping | Need to specify correct CPU, memory, time, account, logs, and failure handling |
| `future.batchtools` / `BiocParallel` | Existing R parallel APIs | Scheduler integration with modest code changes | Application-level resource and reproducibility decisions |
| `targets` + `crew.cluster` | R dependency graph and caching | Rebuilds only outdated targets; dispatches workers | Need for modular functions and correct worker resources |
| `submitit` | Python functions run locally or on SLURM | Submission and array mapping from Python | Need for deterministic functions, storage discipline, and diagnostics |
| Nextflow | Multi-stage file-oriented pipelines | Dependency ordering, parallelism, resume, containers, reports, per-process resources | Need for correct process commands and realistic resource rules |
| Snakemake | Rule-based file workflows | Dependency graph, incremental builds, cluster execution | Need for valid rules, environment management, and capacity planning |

## Signs that raw SLURM is still enough

- Each task is independent and uses the same resource envelope.
- One manifest and one combine step express the workflow clearly.
- Failure recovery is simply “fix and rerun these IDs.”
- The pipeline is small enough that job IDs and outputs remain understandable.

## Signs to move up a layer

- Many stages form a dependency graph rather than a single fan-out/fan-in.
- Resource needs differ by process or must change dynamically on retry.
- The workflow is run often, shared widely, or must resume after interruption.
- Containers and exact environment capture matter.
- Manual job-ID plumbing has become a source of errors.
- You need per-process reports, caching, or automatic detection of stale outputs.

## Preparation that transfers to every tool

A workflow engine benefits from the same design rules as a good array:

- one modular command per scientific step;
- explicit input and output paths;
- deterministic task identity;
- non-zero exit on failure;
- no hidden interactive assumptions;
- measured resource profiles;
- durable manifests and logs.
