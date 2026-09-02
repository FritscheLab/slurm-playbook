---
layout: default
title: Mental Model
parent: Core Guide
nav_order: 2
---

# One task, many CPUs, or many tasks?

The most common resource mistake is requesting a shape that does not match the program's execution model.

| What the command actually does | Start with |
|---|---|
| Uses one useful thread | One task and one CPU |
| Creates `N` threads or local worker processes on one node | One task, `N` CPUs per task, and an explicit `N`-worker setting |
| Repeats independently over files, traits, seeds, chromosomes, or chunks | One manifest row per work unit and a job array |
| Needs multiple SLURM tasks, MPI, or more than one node | Application-specific ARC guidance; this is outside the playbook's scope |
| Behavior is unclear | A representative profile plus the application's documentation |

## Serial worker

A serial R or Python script typically uses one process and one useful CPU:

```bash
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
```

Requesting eight CPUs does not cause a loop written in serial code to run eight times faster.

## Threaded or local process-pool worker

A threaded application or a single-node process pool can use several CPUs inside one allocation:

```bash
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
```

The program must then be told to use eight threads or local workers. Match library limits to the allocation:

```bash
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export OPENBLAS_NUM_THREADS="$OMP_NUM_THREADS"
export MKL_NUM_THREADS="$OMP_NUM_THREADS"
export NUMEXPR_NUM_THREADS="$OMP_NUM_THREADS"
```

The application's own flag—such as `--threads`, `--cpus`, or `--workers`—usually matters more than the environment variables. Use both only when appropriate for the software stack.

{: .danger }
Hidden thread pools can oversubscribe a node when the job requests one CPU but BLAS, OpenMP, Java, or the application launches many threads. Explicit limits protect other users and make accounting interpretable.

## Multiple SLURM tasks or nodes

MPI and other distributed applications can require several SLURM tasks or nodes. That is different from a local R/Python process pool inside one node. Use the application's official launch guidance and understand whether `srun`, MPI, or a framework controls the workers.

## Independent repetitions

Phenotypes, chromosomes, files, simulations, parameter combinations, and data chunks are usually not threads within one program. They are independent invocations of one worker and belong in a job array.

A good worker contract is:

```text
one task ID + explicit inputs → one deterministic output + one exit code
```

## How to verify behavior

1. Check the program's documentation and help output for thread or worker options.
2. Run a representative job inside an interactive allocation.
3. Inspect process/thread activity with tools such as `htop` when permitted.
4. Compare `TotalCPU` with elapsed time and allocated CPUs after completion.
5. Confirm that changing the thread setting changes performance before requesting more CPUs.

{: .tip }
Low CPU efficiency does not always mean “use fewer CPUs.” A process may be waiting on shared storage. Inspect I/O patterns and logs before changing the request.
