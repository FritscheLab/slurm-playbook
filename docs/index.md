---
layout: default
title: Home
nav_order: 1
has_toc: false
description: "Practical SLURM guidance and a tested synthetic pipeline for single-node CPU workflows."
---

<div class="hero-panel">
  <div>
    <p class="hero-kicker">Fritsche Lab · Practical computing guide</p>
    <h1>SLURM Playbook</h1>
    <p class="fs-5">From one correct local task to right-sized, observable, recoverable parallel computing.</p>
    <p class="hero-actions">
      <a class="btn btn-maize" href="{{ site.baseurl }}{% link slurm-guide/quick-start.md %}">Start here</a>
      <a class="btn btn-outline-light" href="{{ site.baseurl }}{% link example-pipeline.md %}">See how it works</a>
      <a class="btn btn-outline-light" href="{{ site.baseurl }}{% link quick-reference.md %}">Command lookup</a>
    </p>
  </div>
  <img src="{{ site.baseurl }}/assets/images/slurm-grid.svg" alt="Stylized grid representing a throttled SLURM job array">
</div>

This is the lab reference to reach for when you have a concrete question: *How many CPUs should I request? Why is my job pending? How do I rerun only task 11? Where should the combine step run?*

If you can already run a command in a Unix shell, the guide will help you move it into a single-node CPU job or array on U-M's SLURM clusters. It covers serial and threaded programs, single-node process pools, independent work units, one fan-in stage, accounting, and recovery. For MPI, multi-node jobs, GPUs, cluster administration, or project-specific compliance decisions, start with ARC or the appropriate specialist instead.

{: .key }
A good SLURM workflow is **measurable, modular, and recoverable**. Treat each resource request as a hypothesis: pilot it, inspect the evidence, and revise it.

## Start with the problem in front of you

<div class="home-grid">
  <a class="lookup-card" href="{{ site.baseurl }}{% link slurm-guide/mental-model.md %}"><strong>CPU or array?</strong>Decide whether the program is serial, threaded, multi-process, or many independent repetitions.</a>
  <a class="lookup-card" href="{{ site.baseurl }}{% link slurm-guide/resources.md %}"><strong>Right-size a request</strong>Use representative pilots, <code>seff</code>, <code>sacct</code>, MaxRSS, elapsed distributions, and thread settings.</a>
  <a class="lookup-card" href="{{ site.baseurl }}{% link slurm-guide/arrays.md %}"><strong>Parallelize repeated work</strong>Put one stable work unit per manifest row and map rows to array task IDs.</a>
  <a class="lookup-card" href="{{ site.baseurl }}{% link slurm-guide/dependencies.md %}"><strong>Chain pipeline stages</strong>Fan out with an array, then fan in only after every upstream element succeeds.</a>
  <a class="lookup-card" href="{{ site.baseurl }}{% link slurm-guide/troubleshooting.md %}"><strong>Diagnose a failure</strong>Follow the evidence in order: state/reason → logs → exit code → resources → environment → paths/I/O.</a>
  <a class="lookup-card" href="{{ site.baseurl }}{% link example-pipeline.md %}"><strong>Inspect the working example</strong>See how the manifest, worker, safety guard, submission wrappers, and result files fit together.</a>
</div>

## The job lifecycle

```mermaid
stateDiagram-v2
    accTitle: SLURM job lifecycle
    accDescr: A job moves from script creation through submission, pending, running, completion, measurement, and revision.
    state "Write or revise script" as Script
    state "Pending: squeue / scontrol" as Pending
    state "Running: logs / sstat" as Running
    state Outcome <<choice>>
    state "Completed: measure with seff / sacct" as Measure
    state "Diagnose logs and exit code" as Diagnose
    state "Revise request or code" as Revise
    [*] --> Script
    Script --> Pending: sbatch
    Pending --> Running: resources available
    Running --> Outcome: terminal state
    Outcome --> Measure: completed
    Outcome --> Diagnose: failed, timed out, or cancelled
    Measure --> Revise
    Diagnose --> Revise: correct root cause
    Revise --> Script
```

{: .caution }
The scheduler is not the debugger. SLURM tells you **where to look** through state and reason; the application log and exit code tell you what the process actually did.

## Six operating principles

<div class="rule-strip">
  <div class="rule"><span class="rule-number">1</span><span><strong>Prove one task locally.</strong><br>Prefer a small or synthetic smoke test.</span></div>
  <div class="rule"><span class="rule-number">2</span><span><strong>Request only CPUs the code can use.</strong><br>Allocating CPUs does not make serial code parallel.</span></div>
  <div class="rule"><span class="rule-number">3</span><span><strong>Tune from distributions.</strong><br>Use <code>seff</code> and array-wide <code>sacct</code>, not one easy task.</span></div>
  <div class="rule"><span class="rule-number">4</span><span><strong>Represent work in a stable manifest.</strong><br>One auditable row should always mean the same task.</span></div>
  <div class="rule"><span class="rule-number">5</span><span><strong>Throttle arrays and use unique logs.</strong><br>Protect account limits and shared storage.</span></div>
  <div class="rule"><span class="rule-number">6</span><span><strong>Aggregate after success; rerun only failures.</strong><br>Preserve completed work and recover at task granularity.</span></div>
</div>

## A working first path

1. Open [Start Here]({{ site.baseurl }}{% link slurm-guide/quick-start.md %}) and run one synthetic manifest row locally.
2. Run the complete scheduler-free test and confirm the documented `PASS` line.
3. Validate the submission command with `--dry-run`, then perform the small Great Lakes acceptance run when you have an account and partition.

The worked example requires Bash 3.2+ and Python 3.10+. A SLURM account is not needed for the local checkpoints.

{: .cluster }
The example is tested on **Great Lakes**. You can use the same scheduler pattern on Armis2 after checking its current account, partition, storage, billing, and sensitive-data rules in the [U-M Cluster Reference]({{ site.baseurl }}{% link cluster-reference.md %}); a duplicate training run is not needed.

## Optional downloads

- [SLURM tutorial slide deck]({{ site.baseurl }}/assets/downloads/slurm-tutorial-slides.pdf)
- [SLURM session cheatsheets]({{ site.baseurl }}/assets/downloads/slurm-session-cheatsheets.pdf)
- [Runnable example pipeline ZIP]({{ site.baseurl }}/assets/downloads/slurm-example-pipeline.zip)

The ZIP expands to a directory named `slurm-example-pipeline/`. The PDFs are teaching aids; the web pages and tested example are the versions we keep current.

## Improve this resource

If a command is unclear, an example fails, or a U-M policy appears outdated, [open an issue](https://github.com/FritscheLab/slurm-playbook/issues/new). Include the page and non-sensitive evidence, and link an official policy source when reporting policy drift.
