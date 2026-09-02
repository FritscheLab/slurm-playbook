---
layout: default
title: AI-Assisted SLURM
parent: Core Guide
nav_order: 11
---

# AI-assisted SLURM

AI tools can draft batch scripts, explain scheduler output, build accounting summaries, and refactor monolithic pipelines. They are most useful when you supply the execution model and evidence; they are least reliable when asked to guess resources from a script title.

## Good uses

- Turn a known local command into a batch wrapper.
- Add strict shell behavior, context logging, and directory validation.
- Convert a tested worker into a manifest-based array.
- Explain a pending reason or exit code from real `squeue`/`sacct` output.
- Parse array-wide accounting into median, upper-tail, and failure summaries.
- Suggest a diagnostic checklist from element-specific stderr.
- Refactor one large script into testable command-line stages.

## Information to provide

A useful request includes:

```text
Cluster and partition
Account passed separately or placeholder only
Exact local command that already works
Serial/threaded/multi-process behavior
Application thread or worker flag
Representative input size and variability
Measured elapsed time and MaxRSS, if available
Expected number of independent work units
Manifest columns and stable task ID
Output and log naming requirements
Desired concurrency cap
Data sensitivity restrictions
Relevant state, reason, ExitCode, stdout, and stderr
```

## Prompt template

```text
Draft a SLURM batch script and submission wrapper for U-M [Great Lakes/Armis2].
The tested local command is: [COMMAND].
One invocation is [serial/threaded with N threads/multi-process].
Representative measurements are: elapsed [X], MaxRSS [Y], TotalCPU [Z].
There are [N] independent tasks defined by rows in [MANIFEST].
Use SLURM_ARRAY_TASK_ID as the stable task ID, logs/%x_%A_%a.out and .err,
and a maximum of [K] simultaneous tasks.
Pass account and partition at submission time; do not hard-code them.
Use set -Eeuo pipefail, create/check directories before sbatch, print runtime context,
and exit non-zero when an expected output is missing.
Explain every resource request and identify assumptions that require verification.
Do not include data, secrets, PHI, or real shortcodes in the response.
```

## Review checklist for AI-generated jobs

- Does the requested CPU count match actual threads or workers?
- Is the application explicitly configured to honor that count?
- Is memory based on measured MaxRSS or an unexplained large default?
- Is walltime credible for the upper tail?
- Are account and partition passed explicitly without exposing a real shortcode?
- Do log parent directories exist before submission?
- Does the batch shell initialize modules/Conda/R/Python itself?
- Are all paths quoted and rooted in a known working directory?
- Does the worker exit non-zero on failure and validate its output?
- Is array concurrency capped to protect shared I/O?
- Does the combine step check completeness before success?
- Are sensitive data and logs excluded from prompts and external APIs?

{: .danger }
Never paste PHI, restricted data, credentials, shortcodes, private paths that reveal sensitive projects, or unreviewed result files into an external AI service. Armis2 approval does not automatically approve a third-party model or API.
