---
layout: default
title: Core Guide
nav_order: 3
has_children: true
permalink: /slurm-guide/
has_toc: false
---

# Core guide

Use this section after completing [Start Here]({{ site.baseurl }}{% link slurm-guide/quick-start.md %}). It explains the progression from **mental model → robust single job → evidence-based resources → manifest and array → dependency and recovery → accounting and troubleshooting**.

## Learning path

| Page | Use it when you need to… |
|---|---|
| [Start Here]({{ site.baseurl }}{% link slurm-guide/quick-start.md %}) | run the tested onboarding checkpoints before adapting the patterns |
| [Mental model]({{ site.baseurl }}{% link slurm-guide/mental-model.md %}) | distinguish serial code, threaded code, multiple processes, and independent repetitions |
| [Robust single job]({{ site.baseurl }}{% link slurm-guide/single-job.md %}) | create an auditable batch script with safe shell behavior, runtime setup, and unique logs |
| [Resource right-sizing]({{ site.baseurl }}{% link slurm-guide/resources.md %}) | select CPU, memory, walltime, and concurrency from evidence |
| [Arrays and manifests]({{ site.baseurl }}{% link slurm-guide/arrays.md %}) | parallelize phenotypes, files, chromosomes, simulations, or parameter combinations |
| [Dependencies and recovery]({{ site.baseurl }}{% link slurm-guide/dependencies.md %}) | fan out, fan in, verify completeness, and rerun only failed elements |
| [Monitoring and accounting]({{ site.baseurl }}{% link slurm-guide/monitoring.md %}) | understand pending states, inspect live jobs, and compare completed tasks |
| [Troubleshooting]({{ site.baseurl }}{% link slurm-guide/troubleshooting.md %}) | follow a repeatable diagnostic sequence rather than changing resources at random |
| [Storage and compliance]({{ site.baseurl }}{% link slurm-guide/storage.md %}) | stage active data safely and keep PHI/sensitive-data boundaries explicit |
| [Workflow tools]({{ site.baseurl }}{% link slurm-guide/workflow-tools.md %}) | decide when raw arrays are enough and when a workflow manager removes real complexity |
| [AI-assisted SLURM]({{ site.baseurl }}{% link slurm-guide/ai-tools.md %}) | use ChatGPT/Codex as a drafting and diagnostic assistant without surrendering judgment |

{: .tip }
Keep one worker runnable outside SLURM. A clean command-line interface—explicit inputs, one work unit, one output, non-zero exit on failure—is the foundation for arrays, Nextflow, Snakemake, and reliable AI assistance.
