---
layout: default
title: Glossary and Sources
nav_order: 7
has_children: true
has_toc: true
---

# Glossary and sources

Looking up an unfamiliar term? Start with the [Glossary]({{ site.baseurl }}{% link glossary.md %}). Checking a command or policy? Use the primary links below, and please flag anything that has drifted.

## Recommended background: earlier CSG sessions

These earlier CSG training sessions are a useful refresher before this playbook. Together they cover CPU, RAM, disk, profiling tools such as `htop`, `/usr/bin/time`, and `pidstat`, disk I/O, shared-system etiquette, and introductory SLURM concepts.

| Session | Slides | Video |
|---|---|---|
| Profiling your programs & running them on the cluster, Part 1 — Ryan Welch and Daniel Taliun (2018) | [Open slides](https://csg.sph.umich.edu/welchr/lab/talks/cluster/intro-to-cluster#1) | [Watch video](https://www.youtube.com/watch?v=AusNgGMUCLc) |
| Profiling your programs & running them on the cluster, Part 2 — Ryan Welch and Daniel Taliun (2018) | [Open slides](https://csg.sph.umich.edu/welchr/lab/talks/cluster/intro-to-cluster-2#1) | [Watch video](https://www.youtube.com/watch?v=UpheAXD4shs) |

{: .caution }
Use these sessions for durable concepts, not current hardware, login-node, storage, or policy details. For today's Great Lakes and Armis2 rules, use the dated U-M reference below.

## Current lab materials

- [SLURM: From a Single Job to Efficient Parallel Computing]({{ site.baseurl }}/assets/downloads/slurm-tutorial-slides.pdf) — a 23-page teaching deck covering lifecycle, mental models, robust jobs, resource tuning, arrays, dependencies, recovery, troubleshooting, and workflow abstractions.
- [SLURM Session Cheatsheets]({{ site.baseurl }}/assets/downloads/slurm-session-cheatsheets.pdf) — printable command, tuning, troubleshooting, and U-M operational cards.
- [Standalone example pipeline ZIP]({{ site.baseurl }}/assets/downloads/slurm-example-pipeline.zip) — the runnable contents of the repository's `examples/` directory under a `slurm-example-pipeline/` top-level folder.

The web guide and tested repository files are the versions we keep current. The PDFs are handy for teaching, but use the dated [U-M Cluster Reference]({{ site.baseurl }}{% link cluster-reference.md %}) instead of a downloaded card when policy matters.

## U-M operations and policy

Time-sensitive operational statements are centralized in the [U-M Cluster Reference]({{ site.baseurl }}{% link cluster-reference.md %}). These primary pages were last checked for this playbook on September 2, 2026:

- [U-M ARC SLURM User Guide](https://documentation.its.umich.edu/arc-hpc/slurm-user-guide)
- [Great Lakes defaults, partition limits, and storage](https://documentation.its.umich.edu/arc-hpc/greatlakes/user-guide/defaults-limits)
- [Great Lakes policies and billing](https://documentation.its.umich.edu/arc-hpc/greatlakes/policies)
- [Armis2 defaults, partition limits, and storage](https://documentation.its.umich.edu/arc-hpc/armis2/cluster-defaults-partition-limits-storage)
- [Armis2 policies](https://documentation.its.umich.edu/arc-hpc/armis2/policies)
- [Armis2 user guide and sensitive-data scope](https://documentation.its.umich.edu/arc-hpc/armis2)

## SLURM behavior

- [Job arrays](https://slurm.schedmd.com/job_array.html)
- [`sbatch` and dependencies](https://slurm.schedmd.com/sbatch.html)
- [`squeue`](https://slurm.schedmd.com/squeue.html) and [job reason codes](https://slurm.schedmd.com/job_reason_codes.html)
- [`sacct`](https://slurm.schedmd.com/sacct.html)
- [`sstat`](https://slurm.schedmd.com/sstat.html)
- [`scontrol`](https://slurm.schedmd.com/scontrol.html)
- [`scancel`](https://slurm.schedmd.com/scancel.html)
- [CPU and memory request semantics](https://slurm.schedmd.com/mc_support.html)
- [Quick-start command roles](https://slurm.schedmd.com/quickstart.html)
- [Environment behavior FAQ](https://slurm.schedmd.com/faq.html)
- [`seff` contribution source](https://github.com/SchedMD/slurm/blob/master/contribs/seff/seff)

## Workflow layers

These are options to consider when raw arrays stop being the clearest interface. Choose a tool because it removes a recurring problem, not simply because it adds another layer.

| Tool | Useful when… | Primary documentation |
|---|---|---|
| `batchtools` / `future.batchtools` | an existing R parallel workflow needs a scheduler backend | [`batchtools`](https://cran.r-project.org/web/packages/batchtools/index.html) · [`future.batchtools`](https://cran.r-project.org/web/packages/future.batchtools/index.html) |
| `BiocParallel` | Bioconductor code should dispatch through a `BatchtoolsParam` | [`BatchtoolsParam` vignette](https://www.bioconductor.org/packages/release/bioc/vignettes/BiocParallel/inst/doc/BiocParallel_BatchtoolsParam.html) |
| `targets` + `crew.cluster` | an R dependency graph needs distributed workers and incremental rebuilds | [`targets` with `crew`](https://books.ropensci.org/targets/crew.html) · [`crew_options_slurm()`](https://wlandau.github.io/crew.cluster/reference/crew_options_slurm.html) |
| `clustermq` | R function calls need a concise cluster-backed map interface | [`clustermq` user guide](https://mschubert.github.io/clustermq/articles/userguide.html) |
| `submitit` | Python functions should run through one local-or-SLURM interface | [`submitit` project](https://github.com/facebookincubator/submitit) |
| Nextflow | a multi-stage file pipeline needs resume, reports, containers, or per-process resources | [Executors](https://docs.seqera.io/nextflow/executor) · [Processes](https://docs.seqera.io/nextflow/process) · [Reports](https://docs.seqera.io/nextflow/reports) · [Cache and resume](https://docs.seqera.io/nextflow/cache-and-resume) · [Configuration](https://docs.seqera.io/nextflow/config) |
| Snakemake | rule-based file dependencies need incremental execution and a cluster executor | [Executor overview](https://snakemake.readthedocs.io/en/stable/executing/executors.html) |

## How we choose what to trust

- Scheduler syntax and behavior should be supported by current SchedMD documentation or a reproducible test.
- U-M operational facts should be dated, linked to official ARC documentation, and kept in the cluster reference rather than repeated across topic pages.
- Resource recommendations should come from representative accounting evidence, not an unexplained fixed value.
- The six operating principles remain stable: prove locally, match resources to behavior, use stable manifests, throttle arrays, aggregate after success, and recover failed elements.

If a source has changed or a link is broken, [open an issue](https://github.com/FritscheLab/slurm-playbook/issues/new) and include the affected page plus the current official source.
