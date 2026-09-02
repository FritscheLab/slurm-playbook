---
layout: default
title: Glossary
parent: Glossary and Sources
nav_order: 1
---

# Glossary

**Account**  
A SLURM billing/association group used to authorize and track resource use. It can have limits that are stricter than cluster-wide maxima.

**Allocation**  
The CPUs, memory, nodes, GPUs, and time reserved for a job.

**Array job**  
A set of batch elements submitted from one array specification. Each element has a distinct array task ID but shares the initial resource request.

**Array task ID**  
The index exposed as `SLURM_ARRAY_TASK_ID`; use it to select a stable manifest row.

**Batch step**  
The job step that runs the batch script. Memory accounting such as MaxRSS may appear on the `.batch` row.

**Concurrency cap**  
The `%K` portion of an array specification, such as `1-100%8`, limiting simultaneous elements.

**Dependency**  
A scheduler condition controlling when a job becomes eligible. `afterok` waits for successful upstream completion.

**Exit code**  
The process status returned to the shell and SLURM. Zero conventionally means success; non-zero indicates failure or another application-defined condition.

**Fan-out / fan-in**  
A workflow pattern that launches many independent tasks and then aggregates them in one downstream stage.

**Job**  
A request submitted to SLURM containing resource requirements and commands.

**Manifest**  
A table where each stable row defines one independent work unit, including its inputs, parameters, seed, and optional resource class.

**MaxRSS**  
Maximum resident set size, commonly used as evidence of peak physical memory consumption for a task or job step.

**Node**  
A physical computer in the cluster. Login nodes are shared for interaction; compute nodes run scheduled workloads.

**Partition**  
A collection of nodes and policy limits, such as `standard` or `debug`.

**Pending reason**  
The reason SLURM reports for a job that has not started, shown through `%R` in `squeue` or `scontrol show job`.

**Resource class**  
A manifest label grouping tasks with similar CPU, memory, or walltime needs so they can be submitted with separate envelopes.

**Scratch**  
High-performance temporary storage for active work. It is not an archive; check current backup and purge rules in the [U-M Cluster Reference]({{ site.baseurl }}{% link cluster-reference.md %}).

**Task**  
Context-dependent: a scientific work unit, a SLURM task/process, or an array element. This guide says “work unit” when scientific meaning could be confused with `--ntasks`.

**Thread**  
A concurrent execution path inside a process. A threaded program must be configured to match `SLURM_CPUS_PER_TASK`.

**Walltime**  
The hard elapsed-time limit requested for a job, independent of total CPU time.
